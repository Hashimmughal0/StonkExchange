import api from '../../services/api';

export async function fetchWallet() {
  const { data } = await api.get('/wallet/wallet');
  return data.data;
}

export async function fetchPortfolio() {
  const { data } = await api.get('/wallet/portfolio');
  return data.data;
}

export async function deposit(amount) {
  const { data } = await api.post('/wallet/deposit', { amount });
  return data;
}

export async function withdraw(amount) {
  const { data } = await api.post('/wallet/withdraw', { amount });
  return data;
}
