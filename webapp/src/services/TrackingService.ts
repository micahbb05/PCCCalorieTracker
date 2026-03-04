import type { MealEntry } from '../models';

export class TrackingService {
    private static STORAGE_KEY = 'pcc_tracked_meals';

    public static getEntries(): MealEntry[] {
        try {
            const raw = localStorage.getItem(this.STORAGE_KEY);
            if (!raw) return [];
            return JSON.parse(raw);
        } catch (e) {
            console.error('Failed to parse tracked meals', e);
            return [];
        }
    }

    public static addEntry(entry: Omit<MealEntry, 'id' | 'createdAt'>): MealEntry {
        const entries = this.getEntries();
        const newEntry: MealEntry = {
            ...entry,
            id: crypto.randomUUID(),
            createdAt: new Date().toISOString()
        };
        entries.push(newEntry);
        this.saveEntries(entries);
        return newEntry;
    }

    public static removeEntry(id: string): void {
        let entries = this.getEntries();
        entries = entries.filter(e => e.id !== id);
        this.saveEntries(entries);
    }

    public static getTodayEntries(): MealEntry[] {
        const entries = this.getEntries();
        const today = new Date().toDateString();
        return entries.filter(e => new Date(e.createdAt).toDateString() === today);
    }

    private static saveEntries(entries: MealEntry[]): void {
        localStorage.setItem(this.STORAGE_KEY, JSON.stringify(entries));
    }
}
