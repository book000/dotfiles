---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/.editorconfig"
---

# C# Coding Rules

Based on a cross-repository survey of book000 / tomacheese organization C# projects
(github-webhook-bridge, watch-wishlist-sale, IdlingLightManager, ElitesRNGAuraObserver,
VRCXDiscordTracker, ZoomInClass).

## Project Setup

- Use SDK-style `.csproj` (`<Project Sdk="Microsoft.NET.Sdk">`). Legacy-style project
  files (`ToolsVersion`, `packages.config`) are only acceptable in old, unmaintained
  projects — never introduce them in new code
- Set in every project (or hoist to a shared `Directory.Build.props` when a repo has
  multiple projects):
  - `<ImplicitUsings>enable</ImplicitUsings>`
  - `<Nullable>enable</Nullable>`
  - `<GenerateDocumentationFile>true</GenerateDocumentationFile>`
  - `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` (fails the build on
    `.editorconfig` IDE-diagnostic violations, not just formatting)
- Target the latest LTS/STS `net<major>.0` (Windows GUI apps add the Windows TFM,
  e.g. `net10.0-windows` or `net9.0-windows10.0.17763.0`)
- Windows GUI apps (WinForms, etc.): `<OutputType>WinExe</OutputType>`,
  `<PublishSingleFile>true</PublishSingleFile>`, `<DebugType>embedded</DebugType>`.
  A companion self-contained updater project additionally sets
  `<RuntimeIdentifier>win-x64</RuntimeIdentifier>` and `<SelfContained>true</SelfContained>`

## StyleCop

- Add `StyleCop.Analyzers` as a build-time-only analyzer:

  ```xml
  <PackageReference Include="StyleCop.Analyzers" Version="x.y.z">
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    <PrivateAssets>all</PrivateAssets>
  </PackageReference>
  ```

- Provide a `stylecop.json` next to the `.csproj` and reference it with
  `<AdditionalFiles Include="stylecop.json" />`
- Set `"documentationCulture": "ja-JP"` and `"xmlHeader": false` unless the project's
  CLAUDE.md specifies a different documentation language

## `.editorconfig`

- Every repo has its own root `.editorconfig` (`root = true`) — do not rely on a
  shared/central template. When creating a new C# repo, copy the fullest existing
  one (e.g. from `github-webhook-bridge` or `IdlingLightManager`) as the starting point
- Baseline formatting: `indent_style = space`, `indent_size = 4` for `*.cs`
  (`indent_size = 2` for `*.xml`, `*.json`, `*.yaml`, `*.yml`, `*.resx`, `*.pubxml`),
  `end_of_line = crlf`, `charset = utf-8`, `insert_final_newline = true`,
  `trim_trailing_whitespace = true`
- Set almost all Roslyn `IDE*` / `CA*` / `SA*` diagnostics to `warning` severity by
  default. Only relax a rule with an inline comment explaining why (e.g.
  `dotnet_diagnostic.CA1848.severity = none # LoggerMessage デリゲートを使用しなくてもよい`) —
  never disable a rule silently
- It is acceptable to relax documentation-comment rules (`CS1591`, `SA1600`,
  `SA1602`, `SA1611`, `SA1615`, `SA1618`) during incremental adoption, but mark the
  override with a "段階的に対応" (phased rollout) comment so it reads as temporary
- Add a `[tests/**.cs]` (or equivalent glob) section that relaxes test-only
  conventions instead of loosening them globally, e.g.:
  - `dotnet_diagnostic.CA1707.severity = none` — allow underscores in xUnit
    `Method_Scenario_Expected` test names
  - `dotnet_diagnostic.IDE1006.severity = none` — `[Fact]`/`[Theory]` methods don't
    need an `Async` suffix

## Code Style

- File-scoped namespaces (`namespace Foo.Bar;`), not block-scoped
  (`namespace Foo.Bar { ... }`)
- `using` directives outside the namespace, `System.*` usings first, no blank line
  between using groups
- Prefer expression-bodied members (`=>`) when the body fits on one line; prefer
  pattern matching, switch expressions, and target-typed `new()`
- XML doc comments on public/exposed members, written in Japanese unless the
  project's own CLAUDE.md says otherwise
- Suppress a specific, justified diagnostic with
  `[SuppressMessage("Category", "RuleId:Name", Justification = "...")]` rather than a
  blanket `#pragma warning disable`

## Application Structure

- Console/service apps: `Microsoft.Extensions.Hosting` Generic Host
  (`Host.CreateDefaultBuilder()`), DI via `ConfigureServices`, options bound with
  `services.AddOptions<T>().Bind(...).ValidateOnStart()`
- Logging: Serilog (`UseSerilog`), enrich from log context, override noisy
  framework categories (e.g. `MinimumLevel.Override("Microsoft", LogEventLevel.Warning)`)
- Azure Functions projects: `Microsoft.Azure.Functions.Worker` (isolated worker
  model), OpenTelemetry + Azure Monitor exporter for observability

## Testing

- Framework: **xUnit** + **Moq** + **coverlet.collector**
- Test project name: `<ProjectName>.Tests`, referencing the main project via
  `<ProjectReference>`
- Use `[InternalsVisibleTo("<ProjectName>.Tests")]` in the main project (via
  `AssemblyAttribute` in the `.csproj` or `AssemblyInfo`) instead of making members
  `public` just for testability
- Test method names: PascalCase describing behaviour (e.g.
  `RunAsyncCreatedTitleContainsStarred`) or the underscore-separated
  `Method_Scenario_Expected` xUnit convention — both are acceptable within one
  project as long as the `.editorconfig` test-only override permits underscores
- CI enforces a minimum line-coverage threshold (project-specific, e.g. 80%) —
  check for an existing threshold before lowering it

## CI (GitHub Actions)

- Runner: `windows-latest` (required for WinForms / Windows-only TFMs)
- Setup with `actions/setup-dotnet`, pinning `dotnet-version` to the SDK's
  major version with a floating patch (e.g. `"10.0.x"`)
- Steps: `dotnet restore` → `dotnet build --no-restore -c Release` →
  `dotnet test --no-build -c Release`
- Style/format check: `dotnet format <sln> --verify-no-changes --severity warn`
  in CI — this must pass before merge, same as StyleCop warnings at build time
