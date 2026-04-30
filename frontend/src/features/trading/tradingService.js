import api from '../../services/api';

export async function fetchStocks() {
  const { data } = await api.get('/stocks');
  return data.data;
}

export async function fetchStock(ticker) {
  const { data } = await api.get(`/stocks/${ticker}`);
  return data.data;
}

export async function fetchOrderBook(ticker) {
  const { data } = await api.get(`/stocks/${ticker}/orderbook`);
  return data.data;
}

export async function fetchTrades(ticker) {
  const { data } = await api.get(`/stocks/${ticker}/trades`);
  return data.data;
}

export async function fetchPriceChart(ticker) {
  const { data } = await api.get(`/stocks/${ticker}/chart`);
  return data.data;
}

export async function fetchPriceSeries(ticker, limit = 100) {
  const { data } = await api.get(`/stocks/${ticker}/chart`, {
    params: { limit }
  });
  return data.data;
}

export async function placeOrder(payload) {
  const { data } = await api.post('/orders', payload);
  return data;
}

export async function fetchOrders() {
  const { data } = await api.get('/orders');
  return data.data;
}
