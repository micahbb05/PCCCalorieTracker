export type DiningVenue = 'four-winds' | 'varsity' | 'grab-n-go';
export type MenuType = 'breakfast' | 'lunch' | 'dinner';

export interface MenuItem {
    id: string;
    name: string;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
    nutrientValues: Record<string, number>;
    servingAmount: number;
    servingUnit: string;
}

export interface MenuLine {
    id: string;
    name: string;
    items: MenuItem[];
}

export interface NutrisliceMenu {
    lines: MenuLine[];
}

export interface MealEntry {
    id: string;
    name: string;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
    createdAt: string; // ISO string for easy storage
}

export interface UserGoals {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
}
