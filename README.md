# FelpFit iOS — motor nativo

Este projeto é o shell iOS do FelpFit.

- A interface é sempre carregada de `https://felpfit.pages.dev/`.
- O IPA não contém cópia local da interface web.
- Alterações visuais, missões, horários, calendário e regras publicadas no Cloudflare aparecem no app sem recompilar o IPA.
- A camada Swift fornece recursos nativos como AlarmKit e notificações e recebe a agenda da interface online.
- O motor inclui verificação de atualização da interface online e um fluxo animado de atualização, preservando sessão e dados locais.
- A versão 1.5 adiciona notificação nativa de atualização, abertura do fluxo de update ao tocar na notificação e a experiência animada "Veja o que mudou".
- A build 152 mantém o Deep Link `felpfit://`, adiciona imagens de reação do Felmo às notificações locais e preserva os avisos de rotina e AlarmKit existentes.
- O push remoto exige uma assinatura Apple cujo provisioning profile contenha `aps-environment` e as credenciais APNs configuradas no backend Cloudflare.
- Mudanças que adicionem uma capacidade iOS totalmente nova ainda exigem uma nova build nativa.

## Build atual

- Marketing: 1.5.12
- Build nativo: 152
- URL de produção: `https://felpfit.pages.dev/`
