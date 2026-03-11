(function(){const e=document.createElement("link").relList;if(e&&e.supports&&e.supports("modulepreload"))return;for(const i of document.querySelectorAll('link[rel="modulepreload"]'))r(i);new MutationObserver(i=>{for(const s of i)if(s.type==="childList")for(const n of s.addedNodes)n.tagName==="LINK"&&n.rel==="modulepreload"&&r(n)}).observe(document,{childList:!0,subtree:!0});function t(i){const s={};return i.integrity&&(s.integrity=i.integrity),i.referrerPolicy&&(s.referrerPolicy=i.referrerPolicy),i.crossOrigin==="use-credentials"?s.credentials="include":i.crossOrigin==="anonymous"?s.credentials="omit":s.credentials="same-origin",s}function r(i){if(i.ep)return;i.ep=!0;const s=t(i);fetch(i.href,s)}})();class f{static STORAGE_KEY="pcc_tracked_meals";static getEntries(){try{const e=localStorage.getItem(this.STORAGE_KEY);return e?JSON.parse(e):[]}catch(e){return console.error("Failed to parse tracked meals",e),[]}}static addEntry(e){const t=this.getEntries(),r={...e,id:crypto.randomUUID(),createdAt:new Date().toISOString()};return t.push(r),this.saveEntries(t),r}static removeEntry(e){let t=this.getEntries();t=t.filter(r=>r.id!==e),this.saveEntries(t)}static clearTodayEntries(){let e=this.getEntries();const t=new Date().toDateString();e=e.filter(r=>new Date(r.createdAt).toDateString()!==t),this.saveEntries(e)}static getTodayEntries(){const e=this.getEntries(),t=new Date().toDateString();return e.filter(r=>new Date(r.createdAt).toDateString()===t)}static saveEntries(e){localStorage.setItem(this.STORAGE_KEY,JSON.stringify(e))}static getGoals(){try{const e=localStorage.getItem("pcc_user_goals");if(e)return JSON.parse(e)}catch(e){console.error("Failed to parse goals",e)}return{calories:2e3,protein:150,carbs:250,fat:65}}static saveGoals(e){localStorage.setItem("pcc_user_goals",JSON.stringify(e))}}class h{container;constructor(e){this.container=e}render(){const e=f.getTodayEntries(),t=e.reduce((d,c)=>d+c.calories,0),r=e.reduce((d,c)=>d+c.protein,0),i=e.reduce((d,c)=>d+c.carbs,0),s=e.reduce((d,c)=>d+c.fat,0),n=f.getGoals(),l=Math.min(100,t/n.calories*100),u=Math.min(100,r/n.protein*100),o=Math.min(100,i/n.carbs*100),m=Math.min(100,s/n.fat*100);let a=`
      <div class="card" style="padding: 1.5rem 1.75rem;">
        <h2 class="outfit" style="margin-bottom: 1.5rem; font-size: 1.4rem;">Today's Overview</h2>
         <div class="flex-between" style="gap: 2rem;">
           <div class="flex-center" style="position: relative; width: 150px; height: 150px; border-radius: 50%; background: var(--surface); box-shadow: inset 0 2px 10px rgba(0,0,0,0.05);">
             <svg width="150" height="150" style="position: absolute; top:0; left:0; transform: rotate(-90deg);">
                <circle cx="75" cy="75" r="65" stroke="var(--border)" stroke-width="10" fill="none" />
                <circle cx="75" cy="75" r="65" stroke="var(--primary)" stroke-width="10" fill="none" stroke-dasharray="408" stroke-dashoffset="${408-408*l/100}" style="transition: stroke-dashoffset 1.5s cubic-bezier(0.1, 0.8, 0.2, 1); stroke-linecap: round;" />
             </svg>
             <div style="text-align: center; z-index: 1;">
               <div style="font-size: 2rem; font-weight: 700; line-height: 1;">${t}</div>
               <div style="font-size: 0.85rem; color: var(--text-muted); margin-top: 0.2rem;">/ ${n.calories} kcal</div>
             </div>
           </div>
           
           <div class="stack" style="flex: 1; gap: 0.5rem;">
             <!-- Protein -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Protein</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${r}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${n.protein}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${u}%; background: #3b82f6; border-radius: 999px;"></div>
               </div>
             </div>

             <!-- Carbs -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Carbs</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${i}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${n.carbs}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${o}%; background: #10b981; border-radius: 999px;"></div>
               </div>
             </div>

             <!-- Fat -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Fat</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${s}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${n.fat}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${m}%; background: #f59e0b; border-radius: 999px;"></div>
               </div>
             </div>
             
             <button id="btn-edit-goals" style="background: transparent; border: none; font-size: 0.8rem; color: var(--primary); font-weight: 600; cursor: pointer; text-align: left; padding: 0; margin-top: 0.25rem;">Edit Goals</button>
           </div>
         </div>
      </div>

      <div class="stack" style="margin-top: 2rem;">
        <div class="flex-between">
          <h3 class="outfit" style="font-size: 1.3rem;">Recent Meals</h3>
          ${e.length>0?'<button id="btn-clear-today" style="background: transparent; border: none; font-size: 0.8rem; color: #ef4444; font-weight: 600; cursor: pointer;">Clear Today</button>':""}
        </div>
    `;if(e.length===0)a+=`
        <div class="card flex-center" style="padding: 3rem 1rem; border-style: dashed; border-color: rgba(0,0,0,0.1); background: transparent; flex-direction: column;">
           <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-muted); opacity: 0.5; margin-bottom: 1rem;"><circle cx="12" cy="12" r="10"></circle><path d="M12 8v4l3 3"></path></svg>
           <span style="color: var(--text-muted); text-align: center;">No meals tracked today.<br>Visit the Menu to add items.</span>
        </div>
      `;else{const d=[...e].reverse();for(const c of d){const p=new Date(c.createdAt),b=isNaN(p.getTime())?"":p.toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"});a+=`
          <div class="card flex-between interactive" style="padding: 1rem 1.25rem; margin-bottom: 0;">
             <div style="padding-right: 1rem;">
               <div style="font-weight: 600; font-size: 0.95rem;">${c.name}</div>
               <div style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.25rem;">${b?`Today, ${b}`:"Today"}</div>
             </div>
             <div class="stack-sm" style="text-align: right; align-items: flex-end; min-width: 90px; gap: 0.2rem;">
               <div class="badge" style="width: fit-content; background: #f1f5f9; border-color: #cbd5e1; color: var(--text-main);">${c.calories} kcal</div>
               <div style="display: flex; gap: 0.4rem; font-size: 0.7rem; color: var(--text-muted);">
                 <span>${c.protein}P</span>
                 <span>${c.carbs}C</span>
                 <span>${c.fat}F</span>
               </div>
               <button class="btn-delete" data-id="${c.id}" style="background:transparent; border:none; color: #ef4444; font-size: 0.75rem; font-weight:600; cursor:pointer; padding: 0.2rem 0; opacity: 0.8; transition: opacity 0.2s;">Discard</button>
             </div>
          </div>
        `}}a+="</div>",a+=`
          <div id="settings-modal" style="display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 2000; align-items: center; justify-content: center;">
            <div class="card" style="width: 90%; max-width: 350px; background: var(--surface); padding: 1.5rem; margin: 0; animation: fadeIn 0.2s ease;">
              <h3 class="outfit" style="margin-bottom: 1.5rem;">Edit Goals</h3>
              <div class="stack">
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Calories</label>
                  <input type="number" id="input-goal-cals" value="${n.calories}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Protein (g)</label>
                  <input type="number" id="input-goal-pro" value="${n.protein}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Carbs (g)</label>
                  <input type="number" id="input-goal-carbs" value="${n.carbs}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Fat (g)</label>
                  <input type="number" id="input-goal-fat" value="${n.fat}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
              </div>
              <div class="flex-between" style="margin-top: 1.5rem; gap: 1rem;">
                <button id="btn-close-modal" class="glass-btn" style="flex: 1;">Cancel</button>
                <button id="btn-save-goals" class="glass-btn primary" style="flex: 1;">Save</button>
              </div>
            </div>
          </div>
        `,this.container.innerHTML=a,document.getElementById("btn-clear-today")?.addEventListener("click",()=>{confirm("Are you sure you want to discard all meals for today?")&&(f.clearTodayEntries(),this.render())});const g=document.getElementById("settings-modal");document.getElementById("btn-edit-goals")?.addEventListener("click",()=>{g&&(g.style.display="flex")}),document.getElementById("btn-close-modal")?.addEventListener("click",()=>{g&&(g.style.display="none")}),document.getElementById("btn-save-goals")?.addEventListener("click",()=>{f.saveGoals({calories:Number(document.getElementById("input-goal-cals").value),protein:Number(document.getElementById("input-goal-pro").value),carbs:Number(document.getElementById("input-goal-carbs").value),fat:Number(document.getElementById("input-goal-fat").value)}),this.render()}),this.container.querySelectorAll(".btn-delete").forEach(d=>{d.addEventListener("mouseenter",()=>d.style.opacity="1"),d.addEventListener("mouseleave",()=>d.style.opacity="0.8"),d.addEventListener("click",c=>{const p=c.currentTarget.getAttribute("data-id");p&&(f.removeEntry(p),this.render())})})}}class x{static formatPathDate(e){const t=e.getFullYear(),r=String(e.getMonth()+1).padStart(2,"0"),i=String(e.getDate()).padStart(2,"0");return`${t}/${r}/${i}`}static formatIsoDate(e){const t=e.getFullYear(),r=String(e.getMonth()+1).padStart(2,"0"),i=String(e.getDate()).padStart(2,"0");return`${t}-${r}-${i}`}static getMenuTypeSlug(e,t){return e==="grab-n-go"?`gng-${t}`:t}static async fetchMenu(e,t,r=new Date){const i=this.getMenuTypeSlug(e,t),s=this.formatPathDate(r),n=`/api/nutrislice/menu/api/weeks/school/${e}/menu-type/${i}/${s}/`;try{const l=await fetch(n,{headers:{Accept:"application/json"}});if(!l.ok)throw new Error(`Failed to fetch menu: ${l.status}`);const u=await l.json(),o=this.formatIsoDate(r),m=u.days.find(a=>a.date===o);return!m||!m.menu_items?{lines:[]}:this.parseMenu(m.menu_items)}catch(l){throw console.error("Nutrislice fetch error:",l),l}}static parseMenu(e){const t=[];for(const r of e){const i=r.text?.trim()||"";if(r.is_station_header&&i){t.push({id:`line-${t.length+1}`,name:i,items:[]});continue}const s=r.food;if(!s)continue;const n=s.name?.trim()||"";if(!n)continue;const u=s.rounded_nutrition_info||{},o={};for(const[b,y]of Object.entries(u))y!=null&&y>=0&&(o[b]=Math.round(y));const m=o.calories||0,a=o.g_protein||0,g=o.g_carbs||0,d=o.g_fat||0;t.length===0&&t.push({id:"menu",name:"Menu",items:[]});const c=t[t.length-1],p=`${c.id}-item-${c.items.length+1}`;c.items.push({id:s.id?String(s.id):p,name:n,calories:m,protein:a,carbs:g,fat:d,nutrientValues:o,servingAmount:1,servingUnit:s.serving_size_info?.serving_size_unit||"serving"})}return{lines:t.filter(r=>r.items.length>0)}}}class w{container;constructor(e){this.container=e}renderIndex(){this.container.innerHTML=`
      <div class="card interactive" data-venue="four-winds">
        <h2 class="outfit">Four Winds</h2>
        <p style="color: var(--text-muted); font-size: 0.9rem; margin-top: 0.5rem; margin-bottom: 1rem;">Lunch & Dinner</p>
        <button class="glass-btn primary" style="width: 100%; pointer-events: none;">Browse Menu</button>
      </div>
      <div class="card interactive" data-venue="varsity">
        <h2 class="outfit">Varsity</h2>
        <p style="color: var(--text-muted); font-size: 0.9rem; margin-top: 0.5rem; margin-bottom: 1rem;">Breakfast, Lunch & Dinner</p>
        <button class="glass-btn primary" style="width: 100%; pointer-events: none;">Browse Menu</button>
      </div>
      <div class="card interactive" data-venue="grab-n-go">
        <h2 class="outfit">Grab N Go</h2>
        <p style="color: var(--text-muted); font-size: 0.9rem; margin-top: 0.5rem; margin-bottom: 1rem;">Quick items all day</p>
        <button class="glass-btn primary" style="width: 100%; pointer-events: none;">Browse Menu</button>
      </div>
    `,this.container.querySelectorAll(".card").forEach(e=>{e.addEventListener("click",()=>{const t=e.getAttribute("data-venue");this.renderVenueMenu(t)})})}async renderVenueMenu(e){this.container.innerHTML=`
      <button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back</button>
      <div class="flex-center" style="height: 200px;"><span style="color: var(--text-muted); font-weight: 500; font-family: Outfit;">Loading Menu...</span></div>
    `,document.getElementById("btn-back")?.addEventListener("click",()=>this.renderIndex());try{const t=new Date().getHours()>=16;let r=e==="grab-n-go"?"lunch":t?"dinner":"lunch";const i=await x.fetchMenu(e,r);let s=`<button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back to Venues</button>
                  <h2 class="outfit" style="margin-bottom: 1.5rem; text-transform: capitalize; font-size: 1.75rem;">${e.replace(/-/g," ")} Menu</h2>
                  <div class="stack">`;i.lines.length===0&&(s+='<div class="card"><span style="color: var(--text-muted);">No menu items found.</span></div>');for(const[n,l]of i.lines.entries()){s+=`
          <div class="accordion-item" style="margin-top: 1rem;">
            <button class="accordion-header flex-between" style="width: 100%; padding: 1.25rem 1rem; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); cursor: pointer; color: var(--text-main); font-family: 'Outfit', sans-serif; font-size: 1.15rem; transition: all 0.2s;" data-accordion-index="${n}">
              <span style="font-weight: 600; color: var(--primary);">${l.name}</span>
              <svg class="chevron" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1); transform: rotate(0deg); color: var(--text-muted);"><polyline points="6 9 12 15 18 9"></polyline></svg>
            </button>
            <div class="accordion-content stack" id="content-${n}" style="display: none; padding-top: 0.75rem; padding-left: 0.5rem; padding-right: 0.5rem;">
        `;for(const o of l.items){const m=o.nutrientValues?.carbonhydrates||o.nutrientValues?.carbs||0,a=o.nutrientValues?.totalFat||o.nutrientValues?.fat||0;s+=`
            <div class="card flex-between" style="padding: 1rem; margin-bottom: 0;" data-item-id="${o.id}">
              <div style="flex: 1; padding-right: 1rem;">
                <div style="font-weight: 600; font-size: 0.95rem; margin-bottom: 0.25rem;">${o.name}</div>
                <div style="font-size: 0.8rem; color: var(--text-muted); margin-bottom: 0.5rem;">${o.servingAmount} ${o.servingUnit}</div>
                <div style="display: flex; gap: 0.75rem; font-size: 0.75rem; color: var(--text-muted);">
                  <span><strong style="color: var(--text-main);">${o.protein}g</strong> P</span>
                  <span><strong style="color: var(--text-main);">${m}g</strong> C</span>
                  <span><strong style="color: var(--text-main);">${a}g</strong> F</span>
                </div>
              </div>
              <div class="flex-center" style="gap: 1rem;">
                <div class="badge" style="width:fit-content; border: none; background: #e0f2fe; color: #0284c7;">${o.calories} kcal</div>
                <button class="icon-btn add-btn btn-add-item" aria-label="Add item">
                   <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                </button>
              </div>
            </div>
          `}s+="</div></div>"}s+="</div>",this.container.innerHTML=s,document.getElementById("btn-back")?.addEventListener("click",()=>this.renderIndex()),this.container.querySelectorAll(".accordion-header").forEach(n=>{n.addEventListener("click",l=>{const u=l.currentTarget,o=u.getAttribute("data-accordion-index"),m=this.container.querySelector(`#content-${o}`),a=u.querySelector(".chevron");m.style.display==="none"?(m.style.display="flex",a.style.transform="rotate(180deg)",u.style.background="var(--surface-hover)",u.style.borderColor="var(--border)"):(m.style.display="none",a.style.transform="rotate(0deg)",u.style.background="var(--surface)",u.style.borderColor="var(--border)")}),n.addEventListener("mouseenter",()=>{n.style.background="var(--surface-hover)"}),n.addEventListener("mouseleave",()=>{this.container.querySelector(`#content-${n.getAttribute("data-accordion-index")}`).style.display==="none"&&(n.style.background="var(--surface)")})}),this.container.querySelectorAll(".btn-add-item").forEach(n=>{n.addEventListener("click",l=>{const u=l.currentTarget.closest(".card");if(!u)return;const o=u.getAttribute("data-item-id"),a=i.lines.find(g=>g.items.some(d=>d.id===o))?.items.find(g=>g.id===o);if(a){const g=a.nutrientValues?.carbonhydrates||a.nutrientValues?.carbs||0,d=a.nutrientValues?.totalFat||a.nutrientValues?.fat||0;f.addEntry({name:a.name,calories:a.calories,protein:a.protein,carbs:g,fat:d}),this.showToast(`Added ${a.name}`)}})})}catch{this.container.innerHTML=`
        <button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back</button>
        <div class="card" style="border-color: #ef4444; background: #fef2f2;"><span style="color: #b91c1c;">Failed to load dietary menu data. The backend API might be unreachable.</span></div>
      `,document.getElementById("btn-back")?.addEventListener("click",()=>this.renderIndex())}}showToast(e){const t=document.getElementById("toast-container");if(!t)return;const r=document.createElement("div");r.className="toast",r.textContent=e,t.appendChild(r),setTimeout(()=>{r.classList.add("fade-out"),r.addEventListener("animationend",()=>{r.remove()})},2500)}}class k{currentView="tracker";container;trackerComponent;menuComponent;constructor(e){const t=document.getElementById(e);if(!t)throw new Error(`Could not find container with id ${e}`);this.container=t,this.renderShell();const r=document.getElementById("view-content");this.trackerComponent=new h(r),this.menuComponent=new w(r),this.renderCurrentView()}setView(e){if(this.currentView===e)return;this.currentView=e,document.getElementById("tab-tracker")?.classList.toggle("active",e==="tracker"),document.getElementById("tab-menu")?.classList.toggle("active",e==="menu");const t=document.getElementById("view-content");t?(t.style.opacity="0",setTimeout(()=>{this.renderCurrentView(),t.style.opacity="1"},150)):this.renderCurrentView()}renderShell(){this.container.innerHTML=`
      <h1 class="title text-gradient">Calorie Tracker</h1>
      <p class="subtitle">Stay on track. Eat with purpose.</p>
      
      <div class="segmented-control">
        <button class="active" id="tab-tracker">Dashboard</button>
        <button id="tab-menu">Diet & Menu</button>
      </div>

      <div id="view-content" class="animate-fade-in" style="transition: opacity 0.2s ease;">
        <!-- Dynamic content goes here -->
      </div>
      
      <div id="toast-container"></div>
    `,document.getElementById("tab-tracker")?.addEventListener("click",()=>this.setView("tracker")),document.getElementById("tab-menu")?.addEventListener("click",()=>this.setView("menu"))}renderCurrentView(){this.currentView==="tracker"?this.trackerComponent.render():this.menuComponent.renderIndex()}}new k("app");
