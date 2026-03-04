import { TrackingService } from '../services/TrackingService';

export class TrackerComponent {
    private container: HTMLElement;

    constructor(container: HTMLElement) {
        this.container = container;
    }

    public render() {
        const todayEntries = TrackingService.getTodayEntries();
        const totalCalories = todayEntries.reduce((sum, e) => sum + e.calories, 0);
        const totalProtein = todayEntries.reduce((sum, e) => sum + e.protein, 0);

        const goalCals = 2000;
        const progressPercent = Math.min(100, (totalCalories / goalCals) * 100);

        let html = `
      <div class="card" style="padding: 1.5rem 1.75rem;">
        <h2 class="outfit" style="margin-bottom: 1.5rem; font-size: 1.4rem;">Today's Overview</h2>
         <div class="flex-between" style="gap: 2rem;">
           <div class="flex-center" style="position: relative; width: 150px; height: 150px; border-radius: 50%; background: rgba(0,0,0,0.15); box-shadow: inset 0 0 20px rgba(0,0,0,0.1);">
             <svg width="150" height="150" style="position: absolute; top:0; left:0; transform: rotate(-90deg);">
                <circle cx="75" cy="75" r="65" stroke="var(--border)" stroke-width="10" fill="none" />
                <circle cx="75" cy="75" r="65" stroke="var(--primary)" stroke-width="10" fill="none" stroke-dasharray="408" stroke-dashoffset="${408 - (408 * progressPercent / 100)}" style="transition: stroke-dashoffset 1.5s cubic-bezier(0.1, 0.8, 0.2, 1); stroke-linecap: round;" filter="drop-shadow(0 0 4px var(--primary-glow))" />
             </svg>
             <div style="text-align: center; z-index: 1;">
               <div style="font-size: 2rem; font-weight: 700; line-height: 1;">${totalCalories}</div>
               <div style="font-size: 0.85rem; color: var(--text-muted); margin-top: 0.2rem;">/ ${goalCals} kcal</div>
             </div>
           </div>
           
           <div class="stack" style="flex: 1;">
             <div style="background: rgba(0,0,0,0.25); border-radius: 12px; padding: 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.4rem;">
                 <span style="font-size: 0.85rem; color: var(--text-muted); font-weight: 500;">Protein</span>
                 <span style="font-size: 0.9rem; font-weight: 700;">${totalProtein}<span style="font-size:0.75rem; font-weight:400; color:var(--text-muted);">g</span></span>
               </div>
               <div style="height: 6px; background: rgba(255,255,255,0.06); border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${Math.min(100, (totalProtein / 150) * 100)}%; background: linear-gradient(90deg, var(--secondary), #f472b6); border-radius: 999px; box-shadow: 0 0 10px rgba(236,72,153,0.5);"></div>
               </div>
             </div>
             
             <div class="flex-between" style="background: rgba(0,0,0,0.25); border-radius: 12px; padding: 0.85rem; border: 1px solid var(--border);">
               <span style="font-size: 0.85rem; color: var(--text-muted); font-weight: 500;">Items Logged</span>
               <span style="font-size: 1rem; font-weight: 700; color: var(--text-main);">${todayEntries.length}</span>
             </div>
           </div>
         </div>
      </div>

      <div class="stack" style="margin-top: 2rem;">
        <h3 class="outfit" style="font-size: 1.3rem;">Recent Meals</h3>
    `;

        if (todayEntries.length === 0) {
            html += `
        <div class="card flex-center" style="padding: 3rem 1rem; border-style: dashed; border-color: rgba(255,255,255,0.1); background: transparent; opacity: 0.7;">
           <span style="color: var(--text-muted); text-align: center;">No meals tracked today.<br>Visit the Menu to add items.</span>
        </div>
      `;
        } else {
            const sorted = [...todayEntries].reverse();
            for (const entry of sorted) {
                const dateObj = new Date(entry.createdAt);
                const timeStr = isNaN(dateObj.getTime()) ? '' : dateObj.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                html += `
          <div class="card flex-between interactive" style="padding: 1rem 1.25rem; margin-bottom: 0;">
             <div style="padding-right: 1rem;">
               <div style="font-weight: 600; font-size: 0.95rem;">${entry.name}</div>
               <div style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.25rem;">${timeStr ? `Today, ${timeStr}` : 'Today'}</div>
             </div>
             <div class="stack-sm" style="text-align: right; align-items: flex-end; min-width: 80px;">
               <div class="badge" style="width: fit-content; background: rgba(139, 92, 246, 0.15); border-color: rgba(139, 92, 246, 0.3); color: #c4b5fd;">${entry.calories} kcal</div>
               <div style="color: var(--text-muted); font-size: 0.8rem; margin-top: 0.1rem;">${entry.protein}g protein</div>
               <button class="btn-delete" data-id="${entry.id}" style="background:transparent; border:none; color: #ef4444; font-size: 0.75rem; font-weight:600; cursor:pointer; padding: 0.2rem 0; margin-top: 0.25rem; opacity: 0.8; transition: opacity 0.2s;">Discard</button>
             </div>
          </div>
        `;
            }
        }

        html += `</div>`;
        this.container.innerHTML = html;

        // Attach hover effect on delete
        this.container.querySelectorAll('.btn-delete').forEach(btn => {
            btn.addEventListener('mouseenter', () => (btn as HTMLElement).style.opacity = '1');
            btn.addEventListener('mouseleave', () => (btn as HTMLElement).style.opacity = '0.8');

            btn.addEventListener('click', (e) => {
                const id = (e.currentTarget as HTMLElement).getAttribute('data-id');
                if (id) {
                    TrackingService.removeEntry(id);
                    this.render(); // Re-render silently to trigger transition
                }
            });
        });
    }
}
