# FelpFit iOS — motor nativo

Este projeto é o shell iOS do FelpFit.

- A interface é sempre carregada de `https://felpfit.pages.dev/`.
- O IPA não contém cópia local da interface web.
- Alterações visuais, missões, horários, calendário e regras publicadas no Cloudflare aparecem no app sem recompilar o IPA.
- A camada Swift fornece recursos nativos como AlarmKit e notificações e recebe a agenda da interface online.
- O motor inclui verificação de atualização da interface online e um botão **Atualizar** que limpa somente caches web, preservando sessão e dados locais.
- Mudanças que adicionem uma capacidade iOS totalmente nova ainda exigem uma nova build nativa.

## Build atual

- Marketing: 1.4.2
- Build nativo: 144
- URL de produção: `https://felpfit.pages.dev/`
