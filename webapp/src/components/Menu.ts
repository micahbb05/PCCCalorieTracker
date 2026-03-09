import type { DiningVenue } from '../models';
import { NutrisliceService } from '../services/NutrisliceService';
import { TrackingService } from '../services/TrackingService';

export class MenuComponent {
  private container: HTMLElement;

  constructor(container: HTMLElement) {
    this.container = container;
  }

  public renderIndex() {
    this.container.innerHTML = `
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
    `;

    this.container.querySelectorAll('.card').forEach(card => {
      card.addEventListener('click', () => {
        const venue = card.getAttribute('data-venue') as DiningVenue;
        this.renderVenueMenu(venue);
      });
    });
  }

  private async renderVenueMenu(venue: DiningVenue) {
    this.container.innerHTML = `
      <button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back</button>
      <div class="flex-center" style="height: 200px;"><span style="color: var(--text-muted); font-weight: 500; font-family: Outfit;">Loading Menu...</span></div>
    `;

    document.getElementById('btn-back')?.addEventListener('click', () => this.renderIndex());

    try {
      const isPostLunch = new Date().getHours() >= 16;
      let menuType = venue === 'grab-n-go' ? 'lunch' : (isPostLunch ? 'dinner' : 'lunch');
      const menu = await NutrisliceService.fetchMenu(venue, menuType as any);

      let html = `<button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back to Venues</button>
                  <h2 class="outfit" style="margin-bottom: 1.5rem; text-transform: capitalize; font-size: 1.75rem;">${venue.replace(/-/g, ' ')} Menu</h2>
                  <div class="stack">`;

      if (menu.lines.length === 0) {
        html += `<div class="card"><span style="color: var(--text-muted);">No menu items found.</span></div>`;
      }

      for (const [index, line] of menu.lines.entries()) {
        const isOpen = false; // By default, all sections are closed
        html += `
          <div class="accordion-item" style="margin-top: 1rem;">
            <button class="accordion-header flex-between" style="width: 100%; padding: 1.25rem 1rem; background: ${isOpen ? 'var(--surface-hover)' : 'var(--surface)'}; border: 1px solid var(--border); border-radius: var(--radius); cursor: pointer; color: var(--text-main); font-family: 'Outfit', sans-serif; font-size: 1.15rem; transition: all 0.2s;" data-accordion-index="${index}">
              <span style="font-weight: 600; color: var(--primary);">${line.name}</span>
              <svg class="chevron" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1); transform: ${isOpen ? 'rotate(180deg)' : 'rotate(0deg)'}; color: var(--text-muted);"><polyline points="6 9 12 15 18 9"></polyline></svg>
            </button>
            <div class="accordion-content stack" id="content-${index}" style="display: ${isOpen ? 'flex' : 'none'}; padding-top: 0.75rem; padding-left: 0.5rem; padding-right: 0.5rem;">
        `;
        for (const item of line.items) {
          // Attempt to map full macros if they exist on the object, assuming nutrientValues might hold them if the Nutrislice API is extended natively,
          // but for now we'll just mock / parse based on what might be present or default to 0.
          const carbs = item.nutrientValues?.carbonhydrates || item.nutrientValues?.carbs || 0;
          const fat = item.nutrientValues?.totalFat || item.nutrientValues?.fat || 0;

          html += `
            <div class="card flex-between" style="padding: 1rem; margin-bottom: 0;" data-item-id="${item.id}">
              <div style="flex: 1; padding-right: 1rem;">
                <div style="font-weight: 600; font-size: 0.95rem; margin-bottom: 0.25rem;">${item.name}</div>
                <div style="font-size: 0.8rem; color: var(--text-muted); margin-bottom: 0.5rem;">${item.servingAmount} ${item.servingUnit}</div>
                <div style="display: flex; gap: 0.75rem; font-size: 0.75rem; color: var(--text-muted);">
                  <span><strong style="color: var(--text-main);">${item.protein}g</strong> P</span>
                  <span><strong style="color: var(--text-main);">${carbs}g</strong> C</span>
                  <span><strong style="color: var(--text-main);">${fat}g</strong> F</span>
                </div>
              </div>
              <div class="flex-center" style="gap: 1rem;">
                <div class="badge" style="width:fit-content; border: none; background: #e0f2fe; color: #0284c7;">${item.calories} kcal</div>
                <button class="icon-btn add-btn btn-add-item" aria-label="Add item">
                   <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                </button>
              </div>
            </div>
          `;
        }
        html += `</div></div>`;
      }
      html += `</div>`;
      this.container.innerHTML = html;

      document.getElementById('btn-back')?.addEventListener('click', () => this.renderIndex());

      // Add accordion toggle listeners
      this.container.querySelectorAll('.accordion-header').forEach(header => {
        header.addEventListener('click', (e) => {
          const btn = e.currentTarget as HTMLElement;
          const index = btn.getAttribute('data-accordion-index');
          const content = this.container.querySelector(`#content-${index}`) as HTMLElement;
          const chevron = btn.querySelector('.chevron') as HTMLElement;

          if (content.style.display === 'none') {
            content.style.display = 'flex';
            chevron.style.transform = 'rotate(180deg)';
            btn.style.background = 'var(--surface-hover)';
            btn.style.borderColor = 'var(--border)';
          } else {
            content.style.display = 'none';
            chevron.style.transform = 'rotate(0deg)';
            btn.style.background = 'var(--surface)';
            btn.style.borderColor = 'var(--border)';
          }
        });

        // Hover effects
        header.addEventListener('mouseenter', () => { (header as HTMLElement).style.background = 'var(--surface-hover)'; });
        header.addEventListener('mouseleave', () => {
          const content = this.container.querySelector(`#content-${header.getAttribute('data-accordion-index')}`) as HTMLElement;
          if (content.style.display === 'none') {
            (header as HTMLElement).style.background = 'var(--surface)';
          }
        });
      });

      // Add to tracking
      this.container.querySelectorAll('.btn-add-item').forEach(btn => {
        btn.addEventListener('click', (e) => {
          const card = (e.currentTarget as HTMLElement).closest('.card');
          if (!card) return;
          const itemId = card.getAttribute('data-item-id');
          const foundLine = menu.lines.find(l => l.items.some(i => i.id === itemId));
          const foundItem = foundLine?.items.find(i => i.id === itemId);

          if (foundItem) {
            const carbs = foundItem.nutrientValues?.carbonhydrates || foundItem.nutrientValues?.carbs || 0;
            const fat = foundItem.nutrientValues?.totalFat || foundItem.nutrientValues?.fat || 0;

            TrackingService.addEntry({
              name: foundItem.name,
              calories: foundItem.calories,
              protein: foundItem.protein,
              carbs: carbs,
              fat: fat
            });

            this.showToast(`Added ${foundItem.name}`);
          }
        });
      });

    } catch (e) {
      this.container.innerHTML = `
        <button class="glass-btn" id="btn-back" style="margin-bottom: 1rem;">← Back</button>
        <div class="card" style="border-color: #ef4444; background: #fef2f2;"><span style="color: #b91c1c;">Failed to load dietary menu data. The backend API might be unreachable.</span></div>
      `;
      document.getElementById('btn-back')?.addEventListener('click', () => this.renderIndex());
    }
  }

  private showToast(message: string) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;

    container.appendChild(toast);

    setTimeout(() => {
      toast.classList.add('fade-out');
      toast.addEventListener('animationend', () => {
        toast.remove();
      });
    }, 2500);
  }
}
