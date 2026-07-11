---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/*.pubxml"
  - "**/Directory.Build.props"
  - "**/stylecop.json"
---

# C# Coding Rules

## Project Setup

- Use SDK-style `.csproj` (`<Project Sdk="Microsoft.NET.Sdk">`). Legacy-style project
  files (`ToolsVersion`, `packages.config`) are only acceptable in old, unmaintained
  projects — never introduce them in new code
- Set in every project (or hoist to a shared `Directory.Build.props` when a repo has
  multiple projects):
  - `<ImplicitUsings>enable</ImplicitUsings>`
  - `<Nullable>enable</Nullable>`
  - `<GenerateDocumentationFile>true</GenerateDocumentationFile>`
  - `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` (runs `.editorconfig`
    IDE code-style analyzers at build time and surfaces them as build
    warnings/errors at whatever severity `.editorconfig` assigns — combine with
    warning-severity diagnostics below, or `TreatWarningsAsErrors`, to actually
    gate the build)
- Target the latest LTS/STS `net<major>.0` (Windows GUI apps add the Windows TFM,
  `net<major>.0-windows`, optionally suffixed with a target Windows SDK version)
- Windows GUI apps (WinForms, etc.): `<OutputType>WinExe</OutputType>`,
  `<PublishSingleFile>true</PublishSingleFile>`, `<DebugType>embedded</DebugType>`.
  `PublishSingleFile` requires a `RuntimeIdentifier` on any project that publishes
  it — set directly in the `.csproj` or via a publish profile (`.pubxml`). A
  companion self-contained updater project additionally sets `<RuntimeIdentifier>`
  and `<SelfContained>true</SelfContained>`

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
- Set `settings.documentationRules.documentationCulture` to `"ja-JP"` and
  `settings.documentationRules.xmlHeader` to `false` unless the project's
  CLAUDE.md specifies a different documentation language:

  ```json
  { "settings": { "documentationRules": { "documentationCulture": "ja-JP", "xmlHeader": false } } }
  ```

## `.editorconfig`

- Every repo has its own root `.editorconfig` (`root = true`) — do not rely on a
  shared/central template. When creating a new C# repo, copy the fullest existing
  repo's `.editorconfig` as the starting point
- Baseline formatting: `indent_style = space`, `indent_size = 4` for `*.cs`
  (`indent_size = 2` for `*.xml`, `*.json`, `*.yaml`, `*.yml`, `*.resx`, `*.pubxml`),
  `end_of_line = crlf`, `charset = utf-8`, `insert_final_newline = true`,
  `trim_trailing_whitespace = true`
- Set almost all Roslyn `IDE*` / `CA*` / `SA*` diagnostics to `warning` severity by
  default. Only relax a rule with an inline comment explaining why — never disable
  a rule silently
- It is acceptable to relax documentation-comment rules (`CS1591`, `SA1600`,
  `SA1602`, `SA1611`, `SA1615`, `SA1618`) during incremental adoption, but mark the
  override with a `# 段階的に対応` (phased-rollout) comment so it reads as temporary,
  not permanent
- Add a `[tests/**.cs]` (or equivalent glob) section that relaxes test-only
  conventions instead of loosening them globally: allow underscores in xUnit
  `Method_Scenario_Expected` test names (`dotnet_diagnostic.CA1707.severity = none`)
  and drop the `Async`-suffix expectation for `[Fact]`/`[Theory]` methods
  (`dotnet_diagnostic.IDE1006.severity = none`)

## Code Style

- File-scoped namespaces (`namespace Foo.Bar;`), not block-scoped
  (`namespace Foo.Bar { ... }`)
- `using` directives outside the namespace, `System.*` usings first, no blank line
  between using groups
- Prefer expression-bodied members (`=>`) when the body fits on one line; prefer
  pattern matching, switch expressions, and target-typed `new()`
- XML doc comments on public/exposed members, written in English unless the
  project's own CLAUDE.md says otherwise
- Suppress a specific, justified diagnostic with
  `[SuppressMessage("Category", "RuleId:Name", Justification = "...")]` rather than a
  blanket `#pragma warning disable`

## Application Structure

- Console/service apps: `Microsoft.Extensions.Hosting` Generic Host
  (`Host.CreateDefaultBuilder()`), DI via `ConfigureServices`, options bound with
  `services.AddOptions<T>().Bind(...).ValidateOnStart()`
- Logging: Serilog (`UseSerilog`), enrich from log context, override noisy
  framework log categories to a higher minimum level
- Azure Functions projects: `Microsoft.Azure.Functions.Worker` (isolated worker
  model), OpenTelemetry + Azure Monitor exporter for observability

## Testing

- Framework: **xUnit** + **Moq** + **coverlet.collector**
- Test project name: `<ProjectName>.Tests`, referencing the main project via
  `<ProjectReference>`
- Use `[InternalsVisibleTo("<ProjectName>.Tests")]` in the main project (via
  `AssemblyAttribute` in the `.csproj` or `AssemblyInfo`) instead of making members
  `public` just for testability
- Test method names: PascalCase describing behaviour, or the underscore-separated
  `Method_Scenario_Expected` xUnit convention — both are acceptable within one
  project as long as the `.editorconfig` test-only override permits underscores
- CI enforces a minimum line-coverage threshold (project-specific) — check for an
  existing threshold before lowering it

## CI (GitHub Actions)

- Runner: `windows-latest` (required for WinForms / Windows-only TFMs)
- Setup with `actions/setup-dotnet`, pinning `dotnet-version` to the SDK's
  major version with a floating patch (`"<major>.0.x"`)
- Steps: `dotnet restore` → `dotnet build --no-restore -c Release` →
  `dotnet test --no-build -c Release`
- Style/format check: `dotnet format <sln> --verify-no-changes --severity warn`
  in CI — this is the step that actually gates merges on formatting/style,
  since StyleCop/analyzer diagnostics are build-time warnings, not build failures
