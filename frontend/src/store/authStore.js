import { create } from 'zustand';

const token = typeof window !== 'undefined' ? localStorage.getItem('stonk_token') : null;

export const useAuthStore = create((set) => ({
  token,
  user: null,
  hydrated: true,
  setAuth: ({ token: nextToken, user }) => {
    if (typeof window !== 'undefined' && nextToken) {
      localStorage.setItem('stonk_token', nextToken);
    }
    set({ token: nextToken, user });
  },
  clearAuth: () => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('stonk_token');
    }
    set({ token: null, user: null });
  },
  markHydrated: () => set({ hydrated: true })
}));
