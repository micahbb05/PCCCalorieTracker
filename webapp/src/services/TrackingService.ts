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

    public static clearTodayEntries(): void {
        let entries = this.getEntries();
        const today = new Date().toDateString();
        entries = entries.filter(e => new Date(e.createdAt).toDateString() !== today);
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

    public static getGoals(): { calories: number; protein: number; carbs: number; fat: number } {
        try {
            const raw = localStorage.getItem('pcc_user_goals');
            if (raw) return JSON.parse(raw);
        } catch (e) {
            console.error('Failed to parse goals', e);
        }
        return { calories: 2000, protein: 150, carbs: 250, fat: 65 }; // default
    }

    public static saveGoals(goals: { calories: number; protein: number; carbs: number; fat: number }): void {
        localStorage.setItem('pcc_user_goals', JSON.stringify(goals));
    }
}
