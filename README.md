# Neon Notch

App nativo para macOS 26+ que transforma o notch do MacBook em um painel local para agentes, Spotify, métricas e clipboard.

## Daily Driver 0.2

- Primeiro uso retomável com diagnóstico de instalação, helper, Codex, Claude Code, notificações, Automação e início no login.
- Atalho global padrão `Control + Option + Space`, configurável em Ajustes, com navegação integral por teclado.
- Hooks schema v2 deduplicados, snapshots atômicos e retenção local limitada; eventos antigos não repetem alertas após relaunch.
- Notificações de atenção abrem a sessão correspondente e oferecem fallback recuperável na central.

## Executar

Requisitos: macOS 26+, Xcode 26.6+ e Swift 6.3. O comando abaixo continua sendo o fluxo Debug e não altera a instalação pessoal.

```bash
./script/build_and_run.sh
```

O script compila o app e o helper, incorpora `NeonNotchHook` em `Contents/Helpers` e abre o bundle gerado em:

```text
DerivedData/Build/Products/Debug/Neon Notch.app
```

Os hooks do Codex e Claude Code **não são instalados durante o build**. A instalação acontece somente pelo onboarding ou por Ajustes → Integrações, sempre com backup e merge idempotente.

## Instalação pessoal assinada

Na primeira vez, crie a identidade local de code signing no Keychain. O macOS pode pedir sua confirmação:

```bash
./script/setup_local_signing.sh
```

Depois, compile, assine, valide e instale a versão Release em `~/Applications`:

```bash
./script/build_and_install.sh
```

Esse fluxo nunca usa assinatura ad hoc. O helper é assinado antes do app, o bundle é validado com `codesign --deep --strict` e a troca é transacional. A versão instalada anterior permanece recuperável em `~/Applications/Neon Notch.previous.app` após uma atualização bem-sucedida.

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
- `script/build_and_run.sh`: caminho canônico de build/run Debug para Xcode e Codex.
- `script/build_and_install.sh`: build Release, assinatura estável e instalação pessoal transacional.

## Privacidade

- Sem analytics, telemetria remota ou sincronização.
- Hooks persistem apenas fonte, evento, IDs, diretório, timestamp e motivo curto sanitizado.
- Prompts, respostas, comandos e parâmetros de ferramentas não entram no log.
- Clipboard ignora tipos confidenciais/transitórios e apps configurados pelo usuário.
- Arquivos copiados são referenciados; não são duplicados.
- Capas do Spotify são armazenadas somente no cache local do app.

O App Sandbox permanece desativado por design. O bundle ID é `com.cammis.NeonNotch`.
