import { useEffect } from 'react';
import { useQuery, useQueryClient } from 'react-query';
import { useNavigate } from 'react-router-dom';
import api from '../services/api';
import { useAuthStore } from '../store/authStore';
import { logoutRequest } from '../features/auth/authService';

export function useAuth() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const token = useAuthStore((state) => state.token);
  const user = useAuthStore((state) => state.user);
  const setAuth = useAuthStore((state) => state.setAuth);
  const clearAuth = useAuthStore((state) => state.clearAuth);
  const markHydrated = useAuthStore((state) => state.markHydrated);

  const meQuery = useQuery({
    queryKey: ['me'],
    queryFn: async () => {
      const { data } = await api.get('/auth/me');
      return data.user;
    },
    enabled: Boolean(token) && !user
  });

  useEffect(() => {
    if (meQuery.data) {
      setAuth({ token, user: meQuery.data });
    }
    markHydrated();
  }, [meQuery.data, markHydrated, setAuth, token]);

  const logout = async () => {
    try {
      await logoutRequest();
    } finally {
      clearAuth();
      // Clear all cached queries so old user data is removed
      queryClient.clear();
      navigate('/login', { replace: true });
    }
  };

  return {
    token,
    user: user ?? meQuery.data ?? null,
    logout,
    clearAuth,
    hydrated: useAuthStore((state) => state.hydrated),
    ...meQuery
  };
}
