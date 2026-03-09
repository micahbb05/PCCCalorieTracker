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
    const totalCarbs = todayEntries.reduce((sum, e) => sum + e.carbs, 0);
    const totalFat = todayEntries.reduce((sum, e) => sum + e.fat, 0);

    const goals = TrackingService.getGoals();
    const progressPercent = Math.min(100, (totalCalories / goals.calories) * 100);

    const proteinPercent = Math.min(100, (totalProtein / goals.protein) * 100);
    const carbsPercent = Math.min(100, (totalCarbs / goals.carbs) * 100);
    const fatPercent = Math.min(100, (totalFat / goals.fat) * 100);

    let html = `
      <div class="card" style="padding: 1.5rem 1.75rem;">
        <h2 class="outfit" style="margin-bottom: 1.5rem; font-size: 1.4rem;">Today's Overview</h2>
         <div class="flex-between" style="gap: 2rem;">
           <div class="flex-center" style="position: relative; width: 150px; height: 150px; border-radius: 50%; background: var(--surface); box-shadow: inset 0 2px 10px rgba(0,0,0,0.05);">
             <svg width="150" height="150" style="position: absolute; top:0; left:0; transform: rotate(-90deg);">
                <circle cx="75" cy="75" r="65" stroke="var(--border)" stroke-width="10" fill="none" />
                <circle cx="75" cy="75" r="65" stroke="var(--primary)" stroke-width="10" fill="none" stroke-dasharray="408" stroke-dashoffset="${408 - (408 * progressPercent / 100)}" style="transition: stroke-dashoffset 1.5s cubic-bezier(0.1, 0.8, 0.2, 1); stroke-linecap: round;" />
             </svg>
             <div style="text-align: center; z-index: 1;">
               <div style="font-size: 2rem; font-weight: 700; line-height: 1;">${totalCalories}</div>
               <div style="font-size: 0.85rem; color: var(--text-muted); margin-top: 0.2rem;">/ ${goals.calories} kcal</div>
             </div>
           </div>
           
           <div class="stack" style="flex: 1; gap: 0.5rem;">
             <!-- Protein -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Protein</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${totalProtein}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${goals.protein}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${proteinPercent}%; background: #3b82f6; border-radius: 999px;"></div>
               </div>
             </div>

             <!-- Carbs -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Carbs</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${totalCarbs}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${goals.carbs}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${carbsPercent}%; background: #10b981; border-radius: 999px;"></div>
               </div>
             </div>

             <!-- Fat -->
             <div style="background: var(--surface-hover); border-radius: 8px; padding: 0.6rem 0.85rem; border: 1px solid var(--border);">
               <div class="flex-between" style="margin-bottom: 0.25rem;">
                 <span style="font-size: 0.8rem; color: var(--text-muted); font-weight: 500;">Fat</span>
                 <span style="font-size: 0.85rem; font-weight: 600;">${totalFat}<span style="font-size:0.7rem; font-weight:400; color:var(--text-muted);">/${goals.fat}g</span></span>
               </div>
               <div style="height: 4px; background: #e5e7eb; border-radius: 999px; overflow: hidden;">
                 <div style="height: 100%; width: ${fatPercent}%; background: #f59e0b; border-radius: 999px;"></div>
               </div>
             </div>
             
             <button id="btn-edit-goals" style="background: transparent; border: none; font-size: 0.8rem; color: var(--primary); font-weight: 600; cursor: pointer; text-align: left; padding: 0; margin-top: 0.25rem;">Edit Goals</button>
           </div>
         </div>
      </div>

      <div class="stack" style="margin-top: 2rem;">
        <div class="flex-between">
          <h3 class="outfit" style="font-size: 1.3rem;">Recent Meals</h3>
          ${todayEntries.length > 0 ? `<button id="btn-clear-today" style="background: transparent; border: none; font-size: 0.8rem; color: #ef4444; font-weight: 600; cursor: pointer;">Clear Today</button>` : ''}
        </div>
    `;

    if (todayEntries.length === 0) {
      html += `
        <div class="card flex-center" style="padding: 3rem 1rem; border-style: dashed; border-color: rgba(0,0,0,0.1); background: transparent; flex-direction: column;">
           <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-muted); opacity: 0.5; margin-bottom: 1rem;"><circle cx="12" cy="12" r="10"></circle><path d="M12 8v4l3 3"></path></svg>
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
             <div class="stack-sm" style="text-align: right; align-items: flex-end; min-width: 90px; gap: 0.2rem;">
               <div class="badge" style="width: fit-content; background: #f1f5f9; border-color: #cbd5e1; color: var(--text-main);">${entry.calories} kcal</div>
               <div style="display: flex; gap: 0.4rem; font-size: 0.7rem; color: var(--text-muted);">
                 <span>${entry.protein}P</span>
                 <span>${entry.carbs}C</span>
                 <span>${entry.fat}F</span>
               </div>
               <button class="btn-delete" data-id="${entry.id}" style="background:transparent; border:none; color: #ef4444; font-size: 0.75rem; font-weight:600; cursor:pointer; padding: 0.2rem 0; opacity: 0.8; transition: opacity 0.2s;">Discard</button>
             </div>
          </div>
        `;
      }
    }

    html += `</div>`;

    // Settings Modal HTML
    html += `
          <div id="settings-modal" style="display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 2000; align-items: center; justify-content: center;">
            <div class="card" style="width: 90%; max-width: 350px; background: var(--surface); padding: 1.5rem; margin: 0; animation: fadeIn 0.2s ease;">
              <h3 class="outfit" style="margin-bottom: 1.5rem;">Edit Goals</h3>
              <div class="stack">
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Calories</label>
                  <input type="number" id="input-goal-cals" value="${goals.calories}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Protein (g)</label>
                  <input type="number" id="input-goal-pro" value="${goals.protein}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Carbs (g)</label>
                  <input type="number" id="input-goal-carbs" value="${goals.carbs}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
                <div class="flex-between">
                  <label style="font-size: 0.9rem; font-weight: 500;">Fat (g)</label>
                  <input type="number" id="input-goal-fat" value="${goals.fat}" style="width: 80px; padding: 0.4rem; border: 1px solid var(--border); border-radius: 6px; text-align: right;">
                </div>
              </div>
              <div class="flex-between" style="margin-top: 1.5rem; gap: 1rem;">
                <button id="btn-close-modal" class="glass-btn" style="flex: 1;">Cancel</button>
                <button id="btn-save-goals" class="glass-btn primary" style="flex: 1;">Save</button>
              </div>
            </div>
          </div>
        `;

    this.container.innerHTML = html;

    // Clear Today Events
    document.getElementById('btn-clear-today')?.addEventListener('click', () => {
      if (confirm('Are you sure you want to discard all meals for today?')) {
        TrackingService.clearTodayEntries();
        this.render();
      }
    });

    // Settings Modal Events
    const modal = document.getElementById('settings-modal');
    document.getElementById('btn-edit-goals')?.addEventListener('click', () => {
      if (modal) modal.style.display = 'flex';
    });

    document.getElementById('btn-close-modal')?.addEventListener('click', () => {
      if (modal) modal.style.display = 'none';
    });

    document.getElementById('btn-save-goals')?.addEventListener('click', () => {
      TrackingService.saveGoals({
        calories: Number((document.getElementById('input-goal-cals') as HTMLInputElement).value),
        protein: Number((document.getElementById('input-goal-pro') as HTMLInputElement).value),
        carbs: Number((document.getElementById('input-goal-carbs') as HTMLInputElement).value),
        fat: Number((document.getElementById('input-goal-fat') as HTMLInputElement).value),
      });
      this.render(); // re-render to reflect new goals
    });

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
