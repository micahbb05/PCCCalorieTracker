import type { DiningVenue, MenuType, NutrisliceMenu, MenuLine } from '../models';

export class NutrisliceService {
    // private static centralTimeZone = 'America/Chicago'; // Approximation if needed, relying on local for now

    // Format Date to YYYY/MM/DD
    private static formatPathDate(date: Date): string {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}/${m}/${d}`;
    }

    // Format Date to YYYY-MM-DD
    private static formatIsoDate(date: Date): string {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    private static getMenuTypeSlug(venue: DiningVenue, menuType: MenuType): string {
        if (venue === 'grab-n-go') return `gng-${menuType}`;
        return menuType;
    }

    public static async fetchMenu(venue: DiningVenue, menuType: MenuType, date: Date = new Date()): Promise<NutrisliceMenu> {
        const slug = this.getMenuTypeSlug(venue, menuType);
        const datePath = this.formatPathDate(date);
        const url = `/api/nutrislice/menu/api/weeks/school/${venue}/menu-type/${slug}/${datePath}/`;

        try {
            const response = await fetch(url, {
                headers: { 'Accept': 'application/json' }
            });

            if (!response.ok) {
                throw new Error(`Failed to fetch menu: ${response.status}`);
            }

            const data = await response.json();
            const isoDate = this.formatIsoDate(date);

            const today = data.days.find((d: any) => d.date === isoDate);
            if (!today || !today.menu_items) {
                return { lines: [] };
            }

            return this.parseMenu(today.menu_items);
        } catch (error) {
            console.error('Nutrislice fetch error:', error);
            throw error;
        }
    }

    private static parseMenu(items: any[]): NutrisliceMenu {
        const lines: MenuLine[] = [];

        for (const item of items) {
            const text = item.text?.trim() || '';

            if (item.is_station_header && text) {
                lines.push({
                    id: `line-${lines.length + 1}`,
                    name: text,
                    items: []
                });
                continue;
            }

            const food = item.food;
            if (!food) continue;

            const name = food.name?.trim() || '';
            if (!name) continue;

            const roundedInfo = food.rounded_nutrition_info || {};
            const numValues = roundedInfo as Record<string, number | null>;

            const nutrientValues: Record<string, number> = {};
            for (const [k, v] of Object.entries(numValues)) {
                if (v !== null && v !== undefined && v >= 0) {
                    nutrientValues[k] = Math.round(v);
                }
            }

            const calories = nutrientValues['calories'] || 0;
            const protein = nutrientValues['g_protein'] || 0;

            if (lines.length === 0) {
                lines.push({ id: 'menu', name: 'Menu', items: [] });
            }

            const lastLine = lines[lines.length - 1];
            const fallbackId = `${lastLine.id}-item-${lastLine.items.length + 1}`;

            lastLine.items.push({
                id: food.id ? String(food.id) : fallbackId,
                name,
                calories,
                protein,
                nutrientValues,
                servingAmount: 1, // simplified for now
                servingUnit: food.serving_size_info?.serving_size_unit || 'serving',
            });
        }

        return { lines: lines.filter(l => l.items.length > 0) };
    }
}
