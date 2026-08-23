import Foundation

struct FelpFitUpdateExperience {
    static let script = #"""
    (() => {
      if (window.__felpfitUpdateExperience150Installed) return;
      window.__felpfitUpdateExperience150Installed = true;

      const NATIVE_BUILD = 150;
      let activePayload = null;
      let activeStep = 0;

      const postNative = payload => {
        try {
          window.webkit?.messageHandlers?.felpfitNative?.postMessage(payload);
        } catch (error) {
          console.warn("FelpFit 1.5 update bridge:", error);
        }
      };

      const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, ch => ({
        "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"
      }[ch]));

      function versionLabel(payload={}) {
        const value = String(payload.remoteVersion || payload.version || "").trim();
        return value || "1.5";
      }

      function releaseSteps(payload={}) {
        const version = versionLabel(payload);
        const v15 = version.startsWith("1.5");
        if (!v15) {
          return [
            {
              icon:"✨",
              kicker:"NOVA ATUALIZAÇÃO",
              title:`Veja o que mudou na versão ${version}`,
              body:"Uma nova versão do FelpFit está pronta. Passe pelas novidades antes de atualizar.",
              chips:["Novidades","Melhorias","Correções"]
            },
            {
              icon:"⚡",
              kicker:"MAIS RÁPIDO",
              title:"Experiência mais fluida",
              body:"Essa versão inclui melhorias de desempenho, estabilidade e ajustes na experiência do aplicativo.",
              chips:["Desempenho","Estabilidade"]
            },
            {
              icon:"💜",
              kicker:"PRONTO",
              title:"Seu FelpFit está preparado",
              body:"Quando você confirmar, o app limpa somente os caches necessários e carrega a versão nova sem apagar seu login ou seus dados.",
              chips:["Login preservado","Dados preservados"]
            }
          ];
        }

        return [
          {
            icon:"1.5",
            kicker:"FELPFIT 1.5",
            title:"Veja o que mudou na atualização 1.5",
            body:"Essa versão foi feita para deixar o FelpFit mais confiável, mais rápido e mais claro no iPhone.",
            chips:["Nova experiência","Mais estabilidade","Update nativo"]
          },
          {
            icon:"🔔",
            kicker:"ALERTAS",
            title:"Alertas mais rápidos e previsíveis",
            body:"Os controles respondem na hora, as categorias continuam abertas depois do toque e o teste de 30 segundos fica protegido para não ser cancelado por uma sincronização logo em seguida.",
            chips:["Resposta instantânea","Teste protegido","Categorias abertas"]
          },
          {
            icon:"🏆",
            kicker:"PROGRESSO",
            title:"Ranking e rotina mais protegidos",
            body:"A sincronização recebeu proteções contra estados antigos sobrescrevendo dados novos. O fechamento do dia, a hidratação e a recuperação de pontos ficam mais seguros.",
            chips:["Ranking protegido","Sincronização","Hidratação","Fechamento do dia"]
          },
          {
            icon:"💜",
            kicker:"TUDO PRONTO",
            title:"FelpFit 1.5 está pronto.",
            body:"O novo update conversa com o iPhone, preserva seu login e seus dados e limpa somente os caches necessários antes de carregar a versão nova.",
            chips:["Notificação nativa","Sem perder login","Sem resetar dados"]
          }
        ];
      }

      function ensureStyle() {
        if (document.getElementById("ff15-update-style")) return;
        const style = document.createElement("style");
        style.id = "ff15-update-style";
        style.textContent = `
          html.ff15-update-locked,html.ff15-update-locked body{overflow:hidden!important;overscroll-behavior:none!important}.ff15-update-root{position:fixed;inset:0;z-index:2147483000;display:grid;place-items:center;padding:max(14px,env(safe-area-inset-top)) 14px max(14px,env(safe-area-inset-bottom));background:radial-gradient(circle at 50% 12%,rgba(139,92,246,.26),transparent 32%),radial-gradient(circle at 88% 80%,rgba(86,62,190,.16),transparent 34%),rgba(7,7,12,.98);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);animation:ff15Fade .32s ease both;touch-action:pan-y}
          .ff15-update-root.leaving{animation:ff15Leave .25s ease both}
          .ff15-update-card{position:relative;width:min(100%,520px);min-height:min(690px,88dvh);overflow:hidden;border:1px solid rgba(255,255,255,.11);border-radius:30px;background:linear-gradient(160deg,rgba(27,25,39,.98),rgba(12,12,19,.99));box-shadow:0 38px 110px rgba(0,0,0,.62),0 0 70px rgba(139,92,246,.12);display:grid;grid-template-rows:auto 1fr auto}
          .ff15-update-card:before{content:"";position:absolute;width:260px;height:260px;border-radius:999px;right:-100px;top:-110px;background:rgba(139,92,246,.16);filter:blur(8px);pointer-events:none;animation:ff15Orb 5s ease-in-out infinite}
          .ff15-top{position:relative;z-index:2;display:flex;align-items:center;justify-content:space-between;padding:18px 18px 8px}
          .ff15-brand{display:flex;align-items:center;gap:9px;font-weight:950;font-size:12px;letter-spacing:.08em}.ff15-brand-mark{display:grid;place-items:center;width:31px;height:31px;border-radius:10px;background:linear-gradient(135deg,#9c73ff,#5e42cb);color:white;box-shadow:0 10px 28px rgba(139,92,246,.3)}
          .ff15-version{padding:7px 10px;border:1px solid rgba(169,138,255,.22);border-radius:999px;background:rgba(139,92,246,.08);color:#c7b5ff;font-size:9px;font-weight:950;letter-spacing:.08em}
          .ff15-stage{position:relative;z-index:1;padding:20px 24px 18px;display:grid;align-content:center;justify-items:center;text-align:center;min-height:0}
          .ff15-icon-wrap{position:relative;display:grid;place-items:center;width:132px;height:132px;margin-bottom:25px}
          .ff15-ring{position:absolute;inset:0;border-radius:999px;border:1px solid rgba(164,126,255,.22);animation:ff15Pulse 2.5s ease-in-out infinite}.ff15-ring:nth-child(2){inset:13px;animation-delay:.35s}.ff15-ring:nth-child(3){inset:26px;animation-delay:.7s}
          .ff15-icon{position:relative;z-index:2;display:grid;place-items:center;width:82px;height:82px;border-radius:25px;background:linear-gradient(145deg,#a77dff,#6446d8);color:white;font-size:31px;font-weight:1000;box-shadow:0 20px 60px rgba(139,92,246,.38);animation:ff15Float 3s ease-in-out infinite}
          .ff15-kicker{font-size:10px;font-weight:1000;letter-spacing:.18em;color:#a98aff;margin-bottom:9px}
          .ff15-title{margin:0;max-width:420px;font-size:clamp(25px,7vw,38px);line-height:1.03;letter-spacing:-.045em;color:#fff;font-weight:1000}
          .ff15-body{margin:14px 0 0;max-width:420px;color:#aaa8b5;font-size:13px;line-height:1.65;font-weight:600}
          .ff15-chips{display:flex;flex-wrap:wrap;justify-content:center;gap:7px;margin-top:18px}.ff15-chip{border:1px solid rgba(169,138,255,.2);background:rgba(139,92,246,.08);color:#c7b5ff;border-radius:999px;padding:7px 10px;font-size:9px;font-weight:900}
          .ff15-bottom{position:relative;z-index:2;padding:10px 18px 18px}.ff15-progress{display:flex;gap:5px;margin:0 auto 14px;max-width:250px}.ff15-dot{height:4px;flex:1;border-radius:99px;background:rgba(255,255,255,.09);overflow:hidden}.ff15-dot:after{content:"";display:block;width:0;height:100%;background:linear-gradient(90deg,#8b5cf6,#c1a8ff);border-radius:inherit;transition:.35s ease}.ff15-dot.done:after{width:100%}
          .ff15-controls{display:grid;grid-template-columns:auto 1fr;gap:9px}.ff15-back,.ff15-next{height:51px;border-radius:16px;font-weight:950;border:1px solid rgba(255,255,255,.1)}.ff15-back{width:55px;background:rgba(255,255,255,.045);color:#d0cdd8}.ff15-back[disabled]{opacity:.25}.ff15-next{background:linear-gradient(135deg,#9468ff,#6245d0);color:white;border-color:transparent;box-shadow:0 15px 35px rgba(105,71,221,.27);letter-spacing:.02em}.ff15-next:disabled{opacity:.62;animation:none}.ff15-next.final{background:linear-gradient(135deg,#9f76ff,#6f4ee0);animation:ff15Button 2s ease-in-out infinite}.ff15-error{color:#ffb5bd}.ff15-spinner{width:82px;height:82px;border-radius:999px;border:3px solid rgba(255,255,255,.08);border-top-color:#a77dff;animation:ff15Spin .85s linear infinite;box-shadow:0 0 42px rgba(139,92,246,.18)}
          .ff15-stage.swap{animation:ff15Swap .32s cubic-bezier(.2,.8,.2,1) both}
          @keyframes ff15Fade{from{opacity:0}to{opacity:1}}@keyframes ff15Leave{to{opacity:0;transform:scale(.985)}}@keyframes ff15Swap{from{opacity:0;transform:translateX(14px) scale(.985)}to{opacity:1;transform:none}}@keyframes ff15Float{0%,100%{transform:translateY(0) rotate(-2deg)}50%{transform:translateY(-8px) rotate(2deg)}}@keyframes ff15Pulse{0%,100%{transform:scale(.92);opacity:.26}50%{transform:scale(1.05);opacity:.8}}@keyframes ff15Orb{0%,100%{transform:translate(0,0)}50%{transform:translate(-20px,18px)}}@keyframes ff15Button{0%,100%{box-shadow:0 15px 35px rgba(105,71,221,.27)}50%{box-shadow:0 18px 48px rgba(139,92,246,.45)}}@keyframes ff15Spin{to{transform:rotate(360deg)}}
          @media(max-width:520px){.ff15-update-root{padding:0}.ff15-update-card{width:100%;min-height:100dvh;border-radius:0;border:0}.ff15-stage{padding:12px 20px 14px}.ff15-icon-wrap{width:116px;height:116px;margin-bottom:20px}.ff15-icon{width:74px;height:74px;border-radius:23px}.ff15-bottom{padding-bottom:max(16px,env(safe-area-inset-bottom))}}
          @media(prefers-reduced-motion:reduce){.ff15-update-root,.ff15-icon,.ff15-ring,.ff15-update-card:before,.ff15-next.final,.ff15-stage.swap{animation:none!important}}
        `;
        document.head.appendChild(style);
      }

      function closeExperienceAfterSuccess() {
        const root = document.getElementById("ff15-update-root");
        if (!root) return;
        root.classList.add("leaving");
        setTimeout(()=>{root.remove();document.documentElement.classList.remove("ff15-update-locked");activePayload=null;},240);
      }

      function renderStep() {
        const root = document.getElementById("ff15-update-root");
        if (!root || !activePayload) return;
        const stage = root.querySelector(".ff15-stage");
        const steps = releaseSteps(activePayload);
        activeStep = Math.max(0, Math.min(activeStep, steps.length - 1));
        const step = steps[activeStep];
        const last = activeStep === steps.length - 1;
        stage.classList.remove("swap"); void stage.offsetWidth; stage.classList.add("swap");
        const back = root.querySelector(".ff15-back"); const next = root.querySelector(".ff15-next");

        if (activePayload.updating === true) {
          stage.innerHTML = `<div class="ff15-icon-wrap"><div class="ff15-spinner"></div></div><div class="ff15-kicker">APLICANDO UPDATE</div><h2 class="ff15-title">Carregando o FelpFit ${escapeHtml(versionLabel(activePayload))}…</h2><p class="ff15-body">Estamos atualizando somente os caches necessários. Seu login e seus dados continuam preservados.</p>`;
          back.disabled = true; next.disabled = true; next.classList.add("final"); next.textContent = "ATUALIZANDO…";
          return;
        }

        if (activePayload.error) {
          stage.innerHTML = `<div class="ff15-icon-wrap"><div class="ff15-ring"></div><div class="ff15-ring"></div><div class="ff15-icon">↻</div></div><div class="ff15-kicker ff15-error">UPDATE NÃO CONCLUÍDO</div><h2 class="ff15-title">Vamos tentar de novo.</h2><p class="ff15-body">${escapeHtml(activePayload.error)}</p><div class="ff15-chips"><span class="ff15-chip">Login preservado</span><span class="ff15-chip">Dados preservados</span></div>`;
          back.disabled = true; next.disabled = false; next.classList.add("final"); next.textContent = "TENTAR NOVAMENTE";
          next.onclick = () => { next.disabled=true; next.textContent="ATUALIZANDO…"; postNative({command:"applyWebUpdate",version:versionLabel(activePayload)}); };
          return;
        }

        stage.innerHTML = `<div class="ff15-icon-wrap"><div class="ff15-ring"></div><div class="ff15-ring"></div><div class="ff15-ring"></div><div class="ff15-icon">${escapeHtml(step.icon)}</div></div><div class="ff15-kicker">${escapeHtml(step.kicker)}</div><h2 class="ff15-title">${escapeHtml(step.title)}</h2><p class="ff15-body">${escapeHtml(step.body)}</p><div class="ff15-chips">${(step.chips||[]).map(c=>`<span class="ff15-chip">${escapeHtml(c)}</span>`).join("")}</div>`;
        root.querySelectorAll(".ff15-dot").forEach((dot,index)=>dot.classList.toggle("done",index<=activeStep));
        back.disabled = activeStep === 0; next.disabled = false; next.classList.toggle("final",last); next.textContent = last ? "ATUALIZAR AGORA" : "PRÓXIMO";
        back.onclick = () => { if (activeStep > 0) { activeStep--; renderStep(); } };
        next.onclick = () => {
          if (!last) { activeStep++; renderStep(); return; }
          const version = versionLabel(activePayload);
          next.disabled = true; next.textContent = "ATUALIZANDO…"; postNative({command:"applyWebUpdate",version});
        };
      }

      function showExperience(payload={}) {
        ensureStyle();
        const sameTarget = activePayload && versionLabel(activePayload) === versionLabel(payload);
        activePayload = sameTarget ? {...activePayload,...payload} : {...payload};
        if (!sameTarget) activeStep = 0;
        document.documentElement.classList.add("ff15-update-locked");
        let root = document.getElementById("ff15-update-root");
        if (!root) {
          root = document.createElement("div"); root.id = "ff15-update-root"; root.className = "ff15-update-root";
          root.innerHTML = `<section class="ff15-update-card" role="dialog" aria-modal="true" aria-label="Atualização obrigatória do FelpFit"><header class="ff15-top"><div class="ff15-brand"><span class="ff15-brand-mark">F</span><span>FELPFIT UPDATE</span></div><span class="ff15-version">OBRIGATÓRIA</span></header><main class="ff15-stage"></main><footer class="ff15-bottom"><div class="ff15-progress"></div><div class="ff15-controls"><button class="ff15-back" type="button" aria-label="Página anterior">‹</button><button class="ff15-next" type="button">PRÓXIMO</button></div></footer></section>`;
          document.body.appendChild(root);
        }
        const steps = releaseSteps(activePayload); root.querySelector(".ff15-progress").innerHTML = steps.map(()=>'<span class="ff15-dot"></span>').join(""); renderStep();
      }

      function installReceiveHook() {
        const original = window.__felpfitNativeReceive;
        if (typeof original !== "function") { setTimeout(installReceiveHook, 40); return; }
        if (original.__ff15Wrapped) return;
        const wrapped = payload => {
          original(payload);
          if (!payload || typeof payload !== "object") return;
          if (payload.type !== "webUpdate") return;
          if (payload.applied === true) setTimeout(closeExperienceAfterSuccess,30);
          else if (payload.available === true && payload.required !== false) setTimeout(()=>showExperience(payload),30);
        };
        wrapped.__ff15Wrapped = true; wrapped.__ff15Original = original; window.__felpfitNativeReceive = wrapped;
      }

      document.addEventListener("keydown",event=>{if(document.getElementById("ff15-update-root")&&event.key==="Escape"){event.preventDefault();event.stopImmediatePropagation();}},true);
      const updateGuardObserver=new MutationObserver(()=>{if(activePayload?.available===true&&!document.getElementById("ff15-update-root"))showExperience(activePayload);});updateGuardObserver.observe(document.documentElement,{childList:true,subtree:true});

      installReceiveHook();
      const capabilityTimer=setInterval(()=>{if(!window.FelpFitNative)return;window.FelpFitNative.nativeBuild=NATIVE_BUILD;const caps=Array.isArray(window.FelpFitNative.capabilities)?window.FelpFitNative.capabilities:[];["update-notifications-v1","release-notes-v1","remote-push-v1","notification-actions-v1","notification-diagnostics-v2"].forEach(cap=>{if(!caps.includes(cap))caps.push(cap);});window.FelpFitNative.capabilities=caps;clearInterval(capabilityTimer);},50);setTimeout(()=>clearInterval(capabilityTimer),5000);
    })();
    """#
}
