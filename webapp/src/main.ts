import './style.css'
import { TrackerComponent } from './components/Tracker';
import { MenuComponent } from './components/Menu';

type View = 'tracker' | 'menu';

class App {
  private currentView: View = 'tracker';
  private container: HTMLElement;

  private trackerComponent: TrackerComponent;
  private menuComponent: MenuComponent;

  constructor(containerId: string) {
    const el = document.getElementById(containerId);
    if (!el) throw new Error(`Could not find container with id ${containerId}`);
    this.container = el;

    // Initialize initial static HTML
    this.renderShell();

    const contentArea = document.getElementById('view-content') as HTMLElement;
    this.trackerComponent = new TrackerComponent(contentArea);
    this.menuComponent = new MenuComponent(contentArea);

    this.renderCurrentView();
  }

  private setView(view: View) {
    if (this.currentView === view) return;
    this.currentView = view;

    // Update tabs
    document.getElementById('tab-tracker')?.classList.toggle('active', view === 'tracker');
    document.getElementById('tab-menu')?.classList.toggle('active', view === 'menu');

    // Slight fade effect
    const content = document.getElementById('view-content');
    if (content) {
      content.style.opacity = '0';
      setTimeout(() => {
        this.renderCurrentView();
        content.style.opacity = '1';
      }, 150);
    } else {
      this.renderCurrentView();
    }
  }

  private renderShell() {
    this.container.innerHTML = `
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
    `;

    // Attach listeners
    document.getElementById('tab-tracker')?.addEventListener('click', () => this.setView('tracker'));
    document.getElementById('tab-menu')?.addEventListener('click', () => this.setView('menu'));
  }

  private renderCurrentView() {
    if (this.currentView === 'tracker') {
      this.trackerComponent.render();
    } else {
      this.menuComponent.renderIndex();
    }
  }
}

new App('app');
