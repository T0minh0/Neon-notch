# Neon Notch

App nativo para macOS 26+ que transforma o notch do MacBook em um painel local para agentes, Spotify, métricas e clipboard.

## Executar

Requisitos: macOS 26+, Xcode 26.6+ e Swift 6.3.

```bash
./script/build_and_run.sh
```

O script compila o app e o helper, incorpora `NeonNotchHook` em `Contents/Helpers` e abre o bundle gerado em:

```text
DerivedData/Build/Products/Debug/Neon Notch.app
```

Os hooks do Codex e Claude Code **não são instalados durante o build**. A instalação acontece somente pelo onboarding ou por Ajustes → Integrações, sempre com backup e merge idempotente.

## Testes

```bash
xcodebuild \
  -project NeonNotch.xcodeproj \
  -scheme NeonNotch \
  -configuration Debug \
  -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Modo de demonstração

O modo usado para screenshots não lê sessões, clipboard ou Spotify reais:

```bash
launchctl setenv NEON_NOTCH_DEMO 1
launchctl setenv NEON_NOTCH_PREVIEW_STATE expanded
launchctl setenv NEON_NOTCH_PREVIEW_SECTION clipboard
open -n 'DerivedData/Build/Products/Debug/Neon Notch.app'
```

Estados aceitos: `collapsed`, `hoverPreview` e `expanded`. No estado expandido, a seção pode ser `agents` ou `clipboard`. Remova as variáveis depois:

```bash
launchctl unsetenv NEON_NOTCH_DEMO
launchctl unsetenv NEON_NOTCH_PREVIEW_STATE
launchctl unsetenv NEON_NOTCH_PREVIEW_SECTION
```

## Estrutura

- `NeonNotch`: app SwiftUI e a ponte AppKit exclusiva do `NSPanel`.
- `NeonNotchHook`: executável pequeno que recebe JSON via stdin e anexa eventos sanitizados em JSONL.
- `NeonNotchTests`: redução de eventos, sanitização, retenção, hashing e ciclo idempotente de configurações.
- `Design`: mock aprovado, capa de demonstração e evidências visuais locais.
- `script/build_and_run.sh`: caminho canônico de build/run para Xcode e Codex.

## Privacidade

- Sem analytics, telemetria remota ou sincronização.
- Hooks persistem apenas fonte, evento, IDs, diretório, timestamp e motivo curto sanitizado.
- Prompts, respostas, comandos e parâmetros de ferramentas não entram no log.
- Clipboard ignora tipos confidenciais/transitórios e apps configurados pelo usuário.
- Arquivos copiados são referenciados; não são duplicados.
- Capas do Spotify são armazenadas somente no cache local do app.

O App Sandbox permanece desativado por design. O bundle ID é `com.cammis.NeonNotch`.
