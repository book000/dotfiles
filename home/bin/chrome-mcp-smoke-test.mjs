#!/usr/bin/env node
import { spawn } from 'node:child_process'
import { delimiter, dirname } from 'node:path'

/**
 * Smoke test CLI の引数を検証する。
 *
 * @param {string[]} args コマンドライン引数
 * @returns {{router: string, browserUrl?: string, project?: string, timeoutSeconds: number}}
 */
function parseArgs(args) {
  const values = new Map()

  for (let index = 0; index < args.length; index += 2) {
    const name = args[index]
    const value = args[index + 1]
    if (!['--router', '--browser-url', '--project', '--timeout-seconds'].includes(name) || !value) {
      throw new Error('Usage: chrome-mcp-smoke-test.mjs --router <path> (--browser-url <url> | --project <name>) --timeout-seconds <seconds>')
    }
    values.set(name, value)
  }

  const router = values.get('--router')
  const browserUrl = values.get('--browser-url')
  const project = values.get('--project')
  const timeoutSeconds = Number(values.get('--timeout-seconds'))
  if (!router || Boolean(browserUrl) === Boolean(project) || !Number.isSafeInteger(timeoutSeconds) || timeoutSeconds < 1) {
    throw new Error('Smoke test arguments are invalid')
  }

  return { router, browserUrl, project, timeoutSeconds }
}

/**
 * detached process group に signal を送る。
 *
 * @param {import('node:child_process').ChildProcess} child smoke test の router process
 * @param {NodeJS.Signals} signal 送信する signal
 */
function signalProcessTree(child, signal) {
  if (!child.pid || child.exitCode !== null) {
    return
  }

  try {
    process.kill(-child.pid, signal)
  } catch (error) {
    if (error.code !== 'ESRCH') {
      child.kill(signal)
    }
  }
}

/**
 * MCP initialize response を検証する。
 *
 * @param {string} line stdout の 1 行
 * @returns {boolean} expected initialize response なら true
 */
function isInitializeResponse(line) {
  try {
    const response = JSON.parse(line)
    return response.jsonrpc === '2.0' && response.id === 1 && typeof response.result === 'object' && response.result !== null
  } catch {
    return false
  }
}

let options
try {
  options = parseArgs(process.argv.slice(2))
} catch (error) {
  console.error(`Error: ${error.message}`)
  process.exit(1)
}

const routerArgs = options.project ? ['--project', options.project] : ['--browserUrl', options.browserUrl]
const child = spawn(options.router, routerArgs, {
  detached: true,
  env: {
    ...process.env,
    PATH: `${dirname(options.router)}${delimiter}${process.env.PATH ?? ''}`,
  },
  stdio: ['pipe', 'pipe', 'pipe'],
})
let completed = false
let closed = false
let resultCode = 1
let stdoutBuffer = ''
let forceStopTimer
let timeoutTimer

/**
 * Smoke test を終了し、必要なら child process tree を停止する。
 *
 * @param {number} code 終了コード
 */
function finish(code) {
  if (completed) {
    return
  }
  completed = true
  resultCode = code
  clearTimeout(timeoutTimer)

  if (code === 0) {
    child.stdin.end()
  } else {
    signalProcessTree(child, 'SIGTERM')
  }

  forceStopTimer = setTimeout(() => {
    signalProcessTree(child, 'SIGKILL')
  }, 1_000)

  if (closed) {
    clearTimeout(forceStopTimer)
    process.exit(resultCode)
  }
}

child.stdout.on('data', (chunk) => {
  stdoutBuffer += chunk
  let newlineIndex
  while ((newlineIndex = stdoutBuffer.indexOf('\n')) !== -1) {
    const line = stdoutBuffer.slice(0, newlineIndex)
    stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1)
    if (isInitializeResponse(line)) {
      finish(0)
      return
    }
  }
})

child.stderr.on('data', () => {})
child.stdin.on('error', () => finish(1))
child.on('error', () => finish(1))
child.on('close', () => {
  closed = true
  if (!completed) {
    finish(1)
    return
  }
  clearTimeout(forceStopTimer)
  process.exit(resultCode)
})

timeoutTimer = setTimeout(() => finish(1), options.timeoutSeconds * 1_000)
child.stdin.write(`${JSON.stringify({
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'chrome-mcp-updater', version: '1.0.0' },
  },
})}\n`)
