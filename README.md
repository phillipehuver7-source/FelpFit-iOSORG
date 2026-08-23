# FelpFit iOS — motor nativo

Este projeto é o shell iOS do FelpFit.

- A interface é sempre carregada de `https://felpfit.pages.dev/`.
- O IPA não contém cópia local da interface web.
- Alterações visuais, missões, horários, calendário e regras publicadas no Cloudflare aparecem no app sem recompilar o IPA.
- A camada Swift fornece recursos nativos como AlarmKit e notificações e recebe a agenda da interface online.
- O motor inclui verificação de atualização da interface online e um fluxo animado de atualização, preservando sessão e dados locais.
- A versão 1.5 adiciona notificação nativa de atualização, abertura do fluxo de update ao tocar na notificação e a experiência animada "Veja o que mudou".
- A build 150 mantém o Deep Link `felpfit://`, padroniza os avisos de rotina no canal local nativo, abre os Ajustes do iPhone corretamente e elimina a corrida que mostrava update já carregado.
- O push remoto exige uma assinatura Apple cujo provisioning profile contenha `aps-environment` e as credenciais APNs configuradas no backend Cloudflare.
- Mudanças que adicionem uma capacidade iOS totalmente nova ainda exigem uma nova build nativa.

## Build atual

- Marketing: 1.5.0
- Build nativo: 150
- URL de produção: `https://felpfit.pages.dev/`
