# Neon Notch — Design QA da silhueta e do standby

## Evidências

- Fonte visual: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/neon-notch-visual-target.png`
- Implementação expandida final: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/implementation-expanded-smoke-v3.png`
- Comparação normalizada: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/design-qa-smoke-comparison.png`
- Standby recolhido: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/implementation-collapsed-standby.png`
- Alerta recolhido: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/implementation-collapsed-alert.png`
- Hover: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/implementation-hover-smoke.png`
- Captura no início da transição de hover: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/implementation-transition-intermediate.png`
- Painel expandido com Agentes e controles de mídia: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/qa-expanded-agents-media.png`
- Painel expandido com Clipboard: `/Users/cammis/Repositorio/Pessoal/Neon-notch/Design/qa-expanded-clipboard.png`

O mock possui `1500 × 1060 px`. O painel foi renderizado em `1120 × 380 pt` numa tela Retina e capturado em `2240 × 760 px` (`@2x`). A comparação tem `1500 × 1642 px` e apresenta os dois artefatos na mesma largura visual. O hover foi capturado em `1200 × 284 px`, correspondente a `600 × 142 pt`.

## Comparação full-view

A implementação mantém a estrutura horizontal do alvo, o recorte central do notch, as três linhas de agentes, métricas laterais e Spotify exclusivamente no rodapé. A base agora é uma única silhueta: o afunilamento começa no topo do rodapé de `72 pt`, usa dois segmentos Bézier por lado e termina com o centro inferior preenchido e as laterais transparentes.

O interior tem base petrol totalmente opaca e gradiente fumê discreto. Na captura, o desktop azul aparece somente fora da forma; nenhuma textura ou texto do desktop é legível dentro do painel. A borda ciano–fúcsia e o brilho interno preservam a direção neon do mock sem transformar o standby em uma cápsula permanente.

## Estados e interação

- Standby: a captura de janela falha por não haver pixels opacos no `NSPanel`; a captura de tela recortada confirma que não existem pontos, cápsula ou halo abaixo do notch.
- Alerta: apenas o contorno de `0,5 pt` acompanha laterais e base do notch. Não há fundo ou indicadores adicionais.
- Hover: a janela já está em `600 × 142 pt` antes do conteúdo ser revelado; a captura inicial e a final não apresentam corte horizontal.
- Mudanças rápidas: a sequência entrar → sair → entrar cancelou o recolhimento pendente e terminou corretamente em `600 × 142 pt`.
- Recolhimento: o conteúdo é ocultado por `160 ms` antes do frame voltar para `notchWidth + 16 pt` por `notchHeight + 8 pt`.
- Spotify expandido: as camadas decorativas não participam do hit-testing e o gesto de expansão não existe enquanto o conteúdo aberto está renderizado. Voltar/Reiniciar, Play/Pause e Próxima mantêm alvos independentes.
- Clipboard expandido: quatro linhas permanecem visíveis sem alterar as métricas ou o rodapé; conteúdo adicional rola dentro da mesma silhueta.

## Superfícies de fidelidade

- Tipografia: SF Pro e pesos atuais foram preservados; nenhum texto novo quebra ou é truncado.
- Espaçamento e ritmo: o corpo termina exatamente no início do rodapé; capa, divisórias, controles e Spotify ficam centralizados numa área útil de `600 pt` e não cruzam as curvas.
- Cores e tokens: ciano, fúcsia e verde mantêm a semântica; o vidro fumê usa apenas cores-base opacas.
- Imagem: a capa mantém recorte e nitidez, agora totalmente dentro da silhueta. Não houve substituição de assets.
- Copy: tarefas, estados e labels existentes foram preservados. O rodapé segue a composição enxuta do mock, sem informações concorrentes.

Uma comparação focada separada não foi necessária: na comparação normalizada a `1500 px`, o rodapé, seus divisores, a capa e o label Spotify permanecem legíveis. As capturas isoladas de hover, alerta e standby cobrem os detalhes que não aparecem no estado expandido.

## Histórico de iteração

### Iteração 1

- [P1] O standby anterior desenhava uma cápsula e dois pontos permanentemente.
  - Correção: remoção integral do fundo e indicadores; criação de um contorno exclusivo para alertas.
  - Evidência pós-fix: `Design/implementation-collapsed-standby.png` e `Design/implementation-collapsed-alert.png`.
- [P1] AppKit e SwiftUI animavam simultaneamente, permitindo conteúdo maior dentro de um frame intermediário pequeno.
  - Correção: `panelState` e `renderedState` separados; resize AppKit imediato antes do reveal e shrink somente após o conceal.
  - Evidência pós-fix: `Design/implementation-transition-intermediate.png` e teste rápido de hover.

### Iteração 2

- [P2] Na primeira curva nova, a capa e o label Spotify ainda tocavam a área transparente inferior.
  - Evidência anterior: `Design/implementation-expanded-smoke-v2.png`.
  - Correção: rodapé alinhado ao mock, com composição compacta em uma única linha e largura útil de `600 pt`.
  - Evidência pós-fix: `Design/implementation-expanded-smoke-v3.png`; todos os elementos ficam dentro da forma.

## Testes

- Build macOS concluído com sucesso.
- Treze testes passaram, cobrindo também comandos rápidos de mídia, o limite exato de cinco horas, pinagem, limpeza e persistência do Clipboard.
- A expansão de hover, o recolhimento e o cancelamento por mudança rápida foram exercitados no app em execução.
- O aviso local sobre CoreSimulator desatualizado não afeta o target macOS nem os testes executados em “My Mac”.

## Findings

- Nenhum finding P0, P1 ou P2 permanece nesta rodada.
- [P3] A intensidade final do halo poderá ser calibrada depois em wallpapers muito claros, sem alterar a geometria.

final result: passed
