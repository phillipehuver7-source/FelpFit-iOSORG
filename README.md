# FelpFit para iOS

Aplicativo iOS do FelpFit usando uma `WKWebView` nativa em tela cheia.

## Fonte da interface

O app carrega diretamente a produção oficial:

`https://felpfit.pages.dev/`

Isso evita congelar uma cópia antiga do HTML dentro do IPA. As atualizações publicadas no Cloudflare Pages passam a aparecer no aplicativo sem precisar gerar um novo IPA para cada mudança visual/web.

## Conta e dados

A `WKWebView` usa armazenamento persistente (`WKWebsiteDataStore.default()`), e o site continua chamando as mesmas Pages Functions e o mesmo banco D1 configurados no projeto Cloudflare. Portanto o login feito dentro do aplicativo acessa a mesma conta e os mesmos dados do site.

## Build

Cada push na branch `main` executa **Build FelpFit IPA** e produz `FelpFit-unsigned.ipa`.
