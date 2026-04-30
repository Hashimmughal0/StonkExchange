import api from '../../services/api';

export async function loginRequest(credentials) {
  const { data } = await api.post('/auth/login', credentials);
  return data;
}

export async function registerRequest(payload) {
  const { data } = await api.post('/auth/register', payload);
  return data;
}

export async function logoutRequest() {
  await api.post('/auth/logout');
}
