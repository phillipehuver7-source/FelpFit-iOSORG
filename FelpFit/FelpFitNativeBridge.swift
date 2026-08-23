import Foundation

struct FelpFitNativeBridge {
    static let script = #"""
    (() => {
      if (window.__felpfitNativeBridgeInstalled) return;
      window.__felpfitNativeBridgeInstalled = true;

      const postNative = (payload) => {
        try {
          window.webkit?.messageHandlers?.felpfitNative?.postMessage(payload);
        } catch (error) {
          console.warn("FelpFit native bridge:", error);
        }
      };

      const DAY_NAMES = {1:"domingo",2:"segunda",3:"terça",4:"quarta",5:"quinta",6:"sexta",7:"sábado"};
      const DAY_SHORT = {1:"Dom",2:"Seg",3:"Ter",4:"Qua",5:"Qui",6:"Sex",7:"Sáb"};
      const ICONS = {
        wake:"⏰", creatine:"💊", school_exit:"🏫", lunch:"🍽️", pre_gym:"🏋️",
        post_gym:"✅", cardio:"🏃", day_status:"⚡", daily_close:"🌙", walk_plan:"🌊",
        walk_done:"✅", energy:"⚡", pre_cardio:"⚡", cardio1:"🏃", cardio2:"🏃",
        food:"🍽️", recovery:"🛌"
      };
      const LABELS = {
        wake:"Acordar", creatine:"Creatina", school_exit:"Saída da escola", lunch:"Almoço",
        pre_gym:"Pré-treino", post_gym:"Treino concluído", cardio:"Cardio", day_status:"Check-in do dia",
        daily_close:"Fechar o dia", walk_plan:"Plano de atividade", walk_done:"Atividade concluída",
        energy:"Energia", pre_cardio:"Energia pré-cardio", cardio1:"Cardio • bloco 1",
        cardio2:"Cardio • bloco 2", food:"Alimentação pós-cardio", recovery:"Recuperação"
      };

      let state = {
        masterEnabled:true,
        notificationStatus:"notDetermined",
        alarmStatus:"notDetermined",
        preferences:{},
        scheduledAlarmCount:0,
        scheduledNotificationCount:0,
        fallbackCount:0,
        webUpdateAvailable:false,
        remoteWebVersion:"",
        currentWebVersion:"",
        nativeBuild:146
      };
      let items = [];
      let lastScheduleSignature = "";

      function hashString(value){
        let hash = 2166136261;
        for(let i=0;i<value.length;i++){
          hash ^= value.charCodeAt(i);
          hash = Math.imul(hash, 16777619);
        }
        return (hash >>> 0).toString(36);
      }

      function dateKey(date){
        const y=date.getFullYear();
        const m=String(date.getMonth()+1).padStart(2,"0");
        const d=String(date.getDate()).padStart(2,"0");
        return `${y}-${m}-${d}`;
      }

      function currentWebVersion(){
        try {
          if(typeof APP_VERSION!=="undefined" && APP_VERSION!==null) return String(APP_VERSION);
        } catch {}
        return String(document.documentElement?.dataset?.appVersion||"");
      }

      function reportWebVersion(){
        const version=currentWebVersion();
        state.currentWebVersion=version;
        postNative({command:"webVersion",version});
      }

      function parseClock(clock){
        const match=String(clock||"").match(/^(\d{2}):(\d{2})$/);
        if(!match) return null;
        return {hour:Number(match[1]),minute:Number(match[2])};
      }

      function shortLabel(question){
        if(String(question.id||"").startsWith("water_")) return "Hidratação";
        return LABELS[question.id] || String(question.text||"Lembrete FelpFit").slice(0,38);
      }

      function itemIcon(question){
        if(String(question.id||"").startsWith("water_")) return "💧";
        return ICONS[question.id] || "🔔";
      }

      function collectMissionItems(){
        if(typeof getScheduledQuestionsForDate !== "function") return [];
        const grouped = new Map();
        const today = new Date();
        today.setHours(12,0,0,0);

        for(let offset=0; offset<7; offset++){
          const day = new Date(today);
          day.setDate(today.getDate()+offset);
          const jsWeekday = day.getDay();
          const calendarWeekday = jsWeekday + 1;
          let questions=[];
          try { questions = getScheduledQuestionsForDate(day) || []; } catch {}

          for(const q of questions){
            const clock=parseClock(q.time);
            if(!clock) continue;
            const category=String(q.id||"").startsWith("water_") ? "hydration" : "mission";
            const signature=[q.id,q.time,q.text||"",q.context||"",category].join("|");
            if(!grouped.has(signature)){
              grouped.set(signature,{
                key:`weekly:${q.id}:${q.time}:${hashString(signature)}`,
                kind:"weekly",
                title:`FelpFit • ${shortLabel(q)}`,
                displayTitle:`${itemIcon(q)} ${shortLabel(q)}`,
                body:[q.text,q.context].filter(Boolean).join(" • "),
                hour:clock.hour,
                minute:clock.minute,
                weekdays:[],
                questionID:String(q.id||""),
                dateKey:"",
                calendarDate:"",
                category,
                sourceText:String(q.text||""),
                time:String(q.time||"")
              });
            }
            const item=grouped.get(signature);
            if(!item.weekdays.includes(calendarWeekday)) item.weekdays.push(calendarWeekday);
          }
        }
        return [...grouped.values()].map(item=>({...item,weekdays:item.weekdays.sort((a,b)=>a-b)}));
      }

      function collectHoldItems(baseItems){
        if(typeof getTodayScheduledEntry !== "function" || typeof getTodayScheduledQuestions !== "function") return [];
        let entry={};
        let questions=[];
        try {
          entry=getTodayScheduledEntry()||{};
          questions=getTodayScheduledQuestions()||[];
        } catch { return []; }

        const today=new Date();
        const calendarWeekday=today.getDay()+1;
        const todayKey=dateKey(today);
        const byId=new Map(questions.map(q=>[String(q.id||""),q]));
        const result=[];
        const now=Date.now();

        const addHolds=(bucket,kindLabel)=>{
          if(!bucket || typeof bucket!=="object") return;
          Object.entries(bucket).forEach(([id,hold])=>{
            if(!hold || !hold.expiresAt) return;
            const q=byId.get(String(id));
            if(!q) return;
            const expires=new Date(hold.expiresAt).getTime();
            if(!Number.isFinite(expires) || expires<=now) return;
            const step=Math.max(1,Number(hold.reminderMinutes||5))*60000;
            let next=new Date(hold.nextPromptAt||Date.now()+step).getTime();
            if(!Number.isFinite(next)) next=now+step;
            next=Math.max(next,now+3000);

            const parent=baseItems.find(item=>item.questionID===String(id) && item.weekdays?.includes(calendarWeekday));
            const preferenceKey=parent?.key || `mission:${calendarWeekday}:${id}`;
            let count=0;
            for(let fire=next; fire<=expires && count<24; fire+=step,count++){
              const d=new Date(fire);
              result.push({
                key:`hold:${todayKey}:${id}:${Math.round(fire)}`,
                preferenceKey,
                kind:"fixed",
                title:`FelpFit • ${shortLabel(q)}`,
                displayTitle:`${itemIcon(q)} ${shortLabel(q)}`,
                body:`${kindLabel}: ${q.text||"Abra o FelpFit para responder."}`,
                hour:d.getHours(),
                minute:d.getMinutes(),
                weekdays:[],
                fireAtMs:fire,
                questionID:String(id),
                dateKey:todayKey,
                calendarDate:"",
                category:"mission",
                sourceText:String(q.text||""),
                time:`${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`,
                hiddenUI:true
              });
            }
          });
        };

        addHolds(entry.deferred,"Lembrete da missão adiada");
        addHolds(entry.inProgress,"Confere a missão em andamento");
        return result;
      }

      function localDateFromKeyAndTime(key,time){
        const [y,m,d]=String(key).split("-").map(Number);
        const clock=parseClock(time);
        if(!y||!m||!d||!clock) return null;
        return new Date(y,m-1,d,clock.hour,clock.minute,0,0);
      }

      function collectCalendarItems(){
        if(typeof getCalendarCustomState !== "function") return [];
        let custom={};
        try { custom=getCalendarCustomState()||{}; } catch { return []; }
        const now=Date.now();
        const max=now+180*24*60*60*1000;
        const result=[];

        Object.entries(custom).sort(([a],[b])=>a.localeCompare(b)).forEach(([key,cfg])=>{
          if(!/^\d{4}-\d{2}-\d{2}$/.test(key) || !cfg || typeof cfg!=="object") return;

          const eventMinutes=Number(cfg.eventReminderMinutes||0);
          if(cfg.startTime && eventMinutes>0){
            const start=localDateFromKeyAndTime(key,cfg.startTime);
            if(start){
              const fire=start.getTime()-eventMinutes*60000;
              if(fire>now+3000 && fire<max){
                const title=String(cfg.title||"Evento do calendário");
                result.push({
                  key:`calendar:event:${key}:${hashString(title+"|"+cfg.startTime)}`,
                  kind:"fixed",
                  title:`FelpFit • ${title.slice(0,42)}`,
                  displayTitle:`📅 ${title}`,
                  body:`Começa às ${cfg.startTime} • aviso ${eventMinutes} min antes`,
                  hour:new Date(fire).getHours(),
                  minute:new Date(fire).getMinutes(),
                  weekdays:[],
                  fireAtMs:fire,
                  questionID:"",
                  dateKey:key,
                  calendarDate:key,
                  category:"calendar",
                  sourceText:title,
                  time:cfg.startTime
                });
              }
            }
          }

          const routine=Array.isArray(cfg.routineItems)?cfg.routineItems:[];
          routine.forEach((entry,index)=>{
            const reminder=Number(entry?.reminderMinutes||0);
            if(!entry?.time || !entry?.action || reminder<=0) return;
            const start=localDateFromKeyAndTime(key,entry.time);
            if(!start) return;
            const fire=start.getTime()-reminder*60000;
            if(fire<=now+3000 || fire>=max) return;
            const action=String(entry.action);
            result.push({
              key:`calendar:routine:${key}:${String(entry.id||index)}:${hashString(action+"|"+entry.time)}`,
              kind:"fixed",
              title:`FelpFit • ${action.slice(0,42)}`,
              displayTitle:`📌 ${action}`,
              body:`Bloco às ${entry.time} • aviso ${reminder} min antes`,
              hour:new Date(fire).getHours(),
              minute:new Date(fire).getMinutes(),
              weekdays:[],
              fireAtMs:fire,
              questionID:"",
              dateKey:key,
              calendarDate:key,
              category:"calendar",
              sourceText:action,
              time:entry.time
            });
          });
        });
        return result;
      }

      function collectSchedule(){
        const base=collectMissionItems();
        return [...base,...collectHoldItems(base),...collectCalendarItems()];
      }

      function statusText(value,type){
        if(value==="authorized" || value==="provisional" || value==="ephemeral") return type==="alarm"?"Alarmes autorizados":"Notificações autorizadas";
        if(value==="denied") return type==="alarm"?"Alarmes bloqueados":"Notificações bloqueadas";
        if(value==="unsupported") return "AlarmKit indisponível";
        return type==="alarm"?"Alarmes aguardando permissão":"Notificações aguardando permissão";
      }

      function statusClass(value){
        if(value==="authorized" || value==="provisional" || value==="ephemeral") return "ok";
        if(value==="denied" || value==="unsupported") return "bad";
        return "wait";
      }

      function dayLabel(weekdays){
        if(!weekdays?.length) return "Data específica";
        const sorted=[...weekdays].sort((a,b)=>a-b);
        const work=[2,3,4,5,6];
        if(JSON.stringify(sorted)===JSON.stringify(work)) return "Seg–Sex";
        if(JSON.stringify(sorted)===JSON.stringify([1,7])) return "Fim de semana";
        return sorted.map(d=>DAY_SHORT[d]||d).join(" • ");
      }

      function preferenceFor(item){
        return state.preferences?.[item.key] || {enabled:true,urgent:true};
      }

      function escapeHtml(value){
        return String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[ch]));
      }

      function rowHtml(item){
        const pref=preferenceFor(item);
        const enabled=pref.enabled!==false;
        const urgent=pref.urgent!==false;
        const when=item.kind==="weekly" ? `${dayLabel(item.weekdays)} • ${item.time}` : `${item.dateKey||""} • ${item.time}`;
        return `
          <div class="ff-native-row ${enabled?"":"off"}">
            <div class="ff-native-row-copy">
              <b>${escapeHtml(item.displayTitle||item.title)}</b>
              <span>${escapeHtml(when)}</span>
              <small>${escapeHtml(item.sourceText||item.body||"")}</small>
            </div>
            <div class="ff-native-row-actions">
              <button type="button" class="ff-switch ${enabled?"on":""}" data-action="enabled" data-key="${escapeHtml(item.key)}" aria-label="Ativar ou desativar aviso">${enabled?"ON":"OFF"}</button>
              <button type="button" class="ff-urgent ${enabled&&urgent?"on":""}" data-action="urgent" data-key="${escapeHtml(item.key)}" ${enabled?"":"disabled"} title="Urgente usa AlarmKit; desligado usa notificação normal">${urgent?"🚨":"🔔"}</button>
            </div>
          </div>`;
      }

      function sectionHtml(title,subtitle,category,open=true){
        const rows=items.filter(item=>item.category===category && !item.hiddenUI);
        if(!rows.length && category==="calendar") return `
          <details class="ff-native-section" ${open?"open":""}>
            <summary><span><b>${title}</b><small>${subtitle}</small></span><em>0</em></summary>
            <div class="ff-native-empty">Nenhum lembrete de calendário opt-in agendado agora.</div>
          </details>`;
        return `
          <details class="ff-native-section" ${open?"open":""}>
            <summary><span><b>${title}</b><small>${subtitle}</small></span><em>${rows.length}</em></summary>
            <div class="ff-native-list">${rows.map(rowHtml).join("")}</div>
          </details>`;
      }

      function ensureStyle(){
        if(document.getElementById("felpfit-native-alert-style")) return;
        const style=document.createElement("style");
        style.id="felpfit-native-alert-style";
        style.textContent=`
          #notificationModal .modal.ff-native-modal{width:min(100%,540px);max-height:min(88dvh,820px);overflow:auto;padding:0;background:linear-gradient(180deg,color-mix(in srgb,var(--panel) 96%,#8b5cf6 4%),var(--panel));}
          .ff-native-head{position:sticky;top:0;z-index:2;padding:20px 20px 14px;background:linear-gradient(180deg,var(--panel) 78%,color-mix(in srgb,var(--panel) 82%,transparent));backdrop-filter:blur(16px);border-bottom:1px solid var(--line)}
          .ff-native-head-top{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.ff-native-head h2{margin:4px 0 4px;font-size:24px}.ff-native-head p{margin:0;color:var(--muted);font-size:12px;line-height:1.45}
          .ff-native-close{width:38px;height:38px;border-radius:13px;border:1px solid var(--line);background:var(--panel3);color:var(--text);font-weight:900;font-size:18px}
          .ff-native-status{display:flex;flex-wrap:wrap;gap:7px;margin-top:13px}.ff-native-chip{padding:7px 9px;border-radius:999px;border:1px solid var(--line);font-size:10px;font-weight:900}.ff-native-chip.ok{color:#9bf6c9;border-color:rgba(66,211,146,.35);background:rgba(66,211,146,.08)}.ff-native-chip.bad{color:#ffabb4;border-color:rgba(255,90,110,.35);background:rgba(255,90,110,.08)}.ff-native-chip.wait{color:#ffe49c;border-color:rgba(245,190,70,.35);background:rgba(245,190,70,.08)}
          .ff-native-body{display:grid;gap:12px;padding:14px 14px 20px}.ff-native-master{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:15px;border:1px solid color-mix(in srgb,var(--accent) 30%,var(--line));border-radius:18px;background:radial-gradient(circle at 100% 0%,rgba(139,92,246,.16),transparent 40%),var(--panel3)}.ff-native-master b{display:block}.ff-native-master small{display:block;margin-top:4px;color:var(--muted);line-height:1.4}
          .ff-native-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}.ff-native-actions button{padding:12px;border-radius:14px;border:1px solid var(--line);background:var(--panel3);color:var(--text);font-weight:850}.ff-native-actions button.primary{background:linear-gradient(135deg,var(--accent),#5d3fc4);border-color:transparent;color:#fff}
          .ff-native-note{padding:12px 13px;border:1px solid var(--line);border-radius:15px;background:var(--panel3);font-size:11px;line-height:1.55;color:var(--muted)}.ff-native-note strong{color:var(--text)}.ff-native-warning{border-color:rgba(245,190,70,.35);color:#ffe7a0;background:rgba(245,190,70,.07)}
          .ff-native-section{border:1px solid var(--line);border-radius:18px;background:var(--panel2);overflow:hidden}.ff-native-section summary{cursor:pointer;list-style:none;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px}.ff-native-section summary::-webkit-details-marker{display:none}.ff-native-section summary span{display:grid;gap:3px}.ff-native-section summary small{color:var(--muted);font-size:10px;font-weight:600}.ff-native-section summary em{font-style:normal;font-size:10px;font-weight:900;padding:5px 7px;border:1px solid var(--line);border-radius:999px;color:var(--accent2)}
          .ff-native-list{display:grid;border-top:1px solid var(--line)}.ff-native-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:12px 13px;border-bottom:1px solid rgba(255,255,255,.055);transition:.2s ease}.ff-native-row:last-child{border-bottom:0}.ff-native-row.off{opacity:.5}.ff-native-row-copy{min-width:0;display:grid;gap:3px}.ff-native-row-copy b{font-size:12px;line-height:1.35}.ff-native-row-copy span{font-size:10px;color:var(--accent2);font-weight:850}.ff-native-row-copy small{font-size:9px;color:var(--muted);line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}.ff-native-row-actions{display:flex;align-items:center;gap:6px;flex:none}.ff-switch,.ff-urgent{height:34px;border-radius:12px;border:1px solid var(--line);background:var(--panel3);color:var(--muted);font-weight:900}.ff-switch{min-width:48px;font-size:10px}.ff-switch.on{color:#a8f3cc;border-color:rgba(66,211,146,.38);background:rgba(66,211,146,.1)}.ff-urgent{width:38px;font-size:16px}.ff-urgent.on{border-color:rgba(255,115,96,.42);background:rgba(255,90,70,.11);box-shadow:0 0 24px rgba(255,90,70,.08)}.ff-urgent:disabled{opacity:.35}.ff-native-empty{padding:14px;border-top:1px solid var(--line);color:var(--muted);font-size:11px}
          .ff-native-toast{position:fixed;left:50%;bottom:max(24px,env(safe-area-inset-bottom));z-index:9999;transform:translate(-50%,20px);opacity:0;pointer-events:none;padding:10px 13px;border:1px solid var(--line);border-radius:14px;background:#15151d;color:#fff;font-size:11px;font-weight:800;box-shadow:0 20px 60px rgba(0,0,0,.4);transition:.25s ease}.ff-native-toast.show{opacity:1;transform:translate(-50%,0)}
          @media(max-width:520px){#notificationModal .modal.ff-native-modal{max-height:92dvh}.ff-native-actions{grid-template-columns:1fr}.ff-native-head{padding:16px 15px 12px}.ff-native-body{padding:12px}.ff-native-row{align-items:flex-start}.ff-native-row-actions{padding-top:2px}}
        `;
        document.head.appendChild(style);
      }

      function toast(message){
        let node=document.getElementById("felpfit-native-toast");
        if(!node){node=document.createElement("div");node.id="felpfit-native-toast";node.className="ff-native-toast";document.body.appendChild(node)}
        node.textContent=String(message||"");
        node.classList.add("show");
        clearTimeout(window.__felpfitNativeToastTimer);
        window.__felpfitNativeToastTimer=setTimeout(()=>node.classList.remove("show"),2600);
      }

      function render(){
        const overlay=document.getElementById("notificationModal");
        if(!overlay) return;
        ensureStyle();
        let modal=overlay.querySelector(".modal");
        if(!modal) return;
        modal.classList.add("ff-native-modal");
        const fallback=Number(state.fallbackCount||0);
        modal.innerHTML=`
          <div class="ff-native-head">
            <div class="ff-native-head-top">
              <div><div class="eyebrow">CENTRAL DE ALERTAS NATIVA</div><h2>FelpFit no seu horário.</h2><p>Agora os avisos vêm do próprio aplicativo. Sem “Adicionar à Tela de Início”.</p></div>
              <button class="ff-native-close" type="button" data-native-close>✕</button>
            </div>
            <div class="ff-native-status">
              <span class="ff-native-chip ${statusClass(state.alarmStatus)}">🚨 ${statusText(state.alarmStatus,"alarm")}</span>
              <span class="ff-native-chip ${statusClass(state.notificationStatus)}">🔔 ${statusText(state.notificationStatus,"notification")}</span>
            </div>
          </div>
          <div class="ff-native-body">
            <div class="ff-native-master">
              <div><b>Alertas neste iPhone</b><small>Desligar aqui pausa alarmes e notificações do FelpFit neste aparelho.</small></div>
              <button type="button" class="ff-switch ${state.masterEnabled!==false?"on":""}" data-native-master>${state.masterEnabled!==false?"ON":"OFF"}</button>
            </div>
            <div class="ff-native-actions">
              <button type="button" class="primary" data-native-permissions>Permitir alarmes + notificações</button>
              <button type="button" data-native-test>Testar em 30 segundos</button>
            </div>
            <div class="ff-native-note"><strong>🚨 Urgente</strong> usa o AlarmKit do iPhone e pode romper Silencioso e Foco. Toque no 🚨 de uma missão para trocar por <strong>🔔 notificação normal</strong>. O botão ON/OFF desliga aquele aviso por completo.</div>
            ${fallback?`<div class="ff-native-note ff-native-warning">⚠️ ${fallback} alerta(s) urgente(s) estão usando notificação normal porque o AlarmKit ficou indisponível ou atingiu o limite do sistema. Missões têm prioridade sobre hidratação e calendário.</div>`:""}
            ${sectionHtml("Missões do dia","Perguntas, treino, energia e fechamento.","mission",true)}
            ${sectionHtml("Hidratação","Os 8 blocos de água também podem tocar.","hydration",false)}
            ${sectionHtml("Calendário personalizado","Só entra aqui o que você marcou com antecedência maior que zero.","calendar",false)}
            <div class="ff-native-note">Agendados agora: <strong>${Number(state.scheduledAlarmCount||0)} urgentes</strong> • <strong>${Number(state.scheduledNotificationCount||0)} normais</strong>. Mudou calendário ou rotina? O app sincroniza novamente sozinho.</div>
          </div>`;

        modal.querySelector("[data-native-close]")?.addEventListener("click",()=>overlay.classList.add("hidden"));
        modal.querySelector("[data-native-master]")?.addEventListener("click",()=>postNative({command:"toggleMaster",enabled:!(state.masterEnabled!==false)}));
        modal.querySelector("[data-native-permissions]")?.addEventListener("click",()=>postNative({command:"requestPermissions"}));
        modal.querySelector("[data-native-test]")?.addEventListener("click",()=>postNative({command:"testAlert"}));
        modal.querySelectorAll("[data-action][data-key]").forEach(button=>{
          button.addEventListener("click",()=>{
            const key=button.dataset.key;
            const pref=preferenceFor({key});
            if(button.dataset.action==="enabled") postNative({command:"toggleEnabled",key,enabled:!(pref.enabled!==false)});
            else postNative({command:"toggleUrgent",key,urgent:!(pref.urgent!==false)});
          });
        });
      }

      function sync(force=false,alwaysPost=false){
        const next=collectSchedule();
        const signature=JSON.stringify(next.map(item=>[item.key,item.preferenceKey||"",item.kind,item.hour,item.minute,item.weekdays,item.fireAtMs||0]));
        items.splice(0,items.length,...next);
        if(force || alwaysPost || signature!==lastScheduleSignature){
          lastScheduleSignature=signature;
          postNative({command:"sync",items:next,force});
        }else{
          postNative({command:"getState"});
        }
      }

      window.__felpfitNativeReceive = (payload) => {
        if(!payload || typeof payload!=="object") return;
        state={...state,...payload};
        if(payload.type==="webUpdate"){
          state.webUpdateAvailable=payload.available===true;
          state.remoteWebVersion=String(payload.remoteVersion||state.remoteWebVersion||"");
        }
        if(payload.message) toast(payload.message);
        if(!document.getElementById("notificationModal")?.classList.contains("hidden")) render();
        const badge=document.getElementById("notificationHomeBadge");
        if(badge) badge.textContent=state.masterEnabled!==false?"nativo":"pausado";
      };

      window.__felpfitNativeKick = () => { reportWebVersion(); sync(false,true); postNative({command:"getCapabilities"}); };
      window.__felpfitNativeSync = () => { reportWebVersion(); sync(false,true); };

      // Keep the existing menu entry, but route it to the native center.
      window.openNotificationSettings = () => {
        try { if(typeof closeMenu==="function") closeMenu(); } catch {}
        const overlay=document.getElementById("notificationModal");
        if(!overlay) return;
        overlay.classList.remove("hidden");
        sync(false);
        render();
      };
      window.closeNotificationSettings = () => document.getElementById("notificationModal")?.classList.add("hidden");

      // Stable contract for future Cloudflare releases. The online app can use
      // these primitives without changing the IPA as long as no brand-new iOS
      // capability is required.
      window.FelpFitNative = Object.assign(window.FelpFitNative||{}, {
        engineVersion:"1.0",
        nativeBuild:146,
        capabilities:["alerts-v1","alarmkit-v1","web-update-v1","remote-alert-sync-v1"],
        syncAlerts:(customItems,force=true)=>postNative({command:"sync",items:Array.isArray(customItems)?customItems:[],force:Boolean(force)}),
        syncCurrentAlerts:(force=true)=>sync(Boolean(force),true),
        getState:()=>postNative({command:"getState"}),
        requestPermissions:()=>postNative({command:"requestPermissions"}),
        testAlert:()=>postNative({command:"testAlert"}),
        checkForUpdate:()=>postNative({command:"checkWebUpdate"})
      });

      // Old PWA push is intentionally not used inside the real iOS app.
      window.enablePushNotifications = () => window.openNotificationSettings();
      window.disablePushNotifications = () => window.openNotificationSettings();
      window.sendPushTest = () => postNative({command:"testAlert"});

      setTimeout(()=>{reportWebVersion();sync(false,false);},900);
      setInterval(()=>sync(false),60000);
    })();
    """#
}
