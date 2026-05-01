import { useMemo, useState } from 'react';
import { useMutation } from 'react-query';
import { Link, useNavigate } from 'react-router-dom';
import { registerRequest } from '../features/auth/authService';
import { useAuthStore } from '../store/authStore';

function validate(values) {
  const errors = {};
  if (!values.username.trim()) {
    errors.username = 'Username is required';
  }
  if (!values.email.trim()) {
    errors.email = 'Email is required';
  } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email)) {
    errors.email = 'Enter a valid email';
  }
  if (!values.password) {
    errors.password = 'Password is required';
  } else if (values.password.length < 8) {
    errors.password = 'Password must be at least 8 characters';
  }
  return errors;
}

export default function RegisterPage() {
  const navigate = useNavigate();
  const setAuth = useAuthStore((state) => state.setAuth);
  const [form, setForm] = useState({ username: '', email: '', password: '' });
  const [touched, setTouched] = useState({});

  const errors = useMemo(() => validate(form), [form]);

  const mutation = useMutation({
    mutationFn: registerRequest,
    onSuccess: (data) => {
      setAuth({ token: data.token, user: data.user });
      navigate('/markets', { replace: true });
    }
  });

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="glass-panel w-full max-w-md p-8 transition duration-300 ease-out hover:-translate-y-0.5">
        <div className="mb-8">
          <p className="text-xs uppercase tracking-[0.3em] text-accent2">StonkExchange</p>
          <h1 className="mt-2 text-3xl font-bold text-white">Create account</h1>
          <p className="mt-2 text-sm text-slate-400">Join the trading dashboard.</p>
        </div>

        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            setTouched({ username: true, email: true, password: true });
            if (Object.keys(errors).length) {
              return;
            }
            mutation.mutate(form);
          }}
        >
          <div>
            <input
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none transition focus:border-accent"
              placeholder="Username"
              value={form.username}
              onChange={(e) => setForm({ ...form, username: e.target.value })}
              onBlur={() => setTouched((prev) => ({ ...prev, username: true }))}
            />
            {touched.username && errors.username ? (
              <p className="mt-2 text-xs text-red">{errors.username}</p>
            ) : null}
          </div>

          <div>
            <input
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none transition focus:border-accent"
              placeholder="Email"
              type="email"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              onBlur={() => setTouched((prev) => ({ ...prev, email: true }))}
            />
            {touched.email && errors.email ? (
              <p className="mt-2 text-xs text-red">{errors.email}</p>
            ) : null}
          </div>

          <div>
            <input
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none transition focus:border-accent"
              placeholder="Password"
              type="password"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              onBlur={() => setTouched((prev) => ({ ...prev, password: true }))}
            />
            {touched.password && errors.password ? (
              <p className="mt-2 text-xs text-red">{errors.password}</p>
            ) : null}
          </div>

          <button
            type="submit"
            className="w-full rounded-xl bg-accent px-4 py-3 text-sm font-semibold text-white transition hover:bg-accent2 disabled:opacity-60"
            disabled={mutation.isLoading}
          >
            {mutation.isLoading ? 'Creating account...' : 'Create account'}
          </button>

          {mutation.isError ? (
            <p className="text-sm text-red">
              {mutation.error?.response?.data?.message || 'Registration failed'}
            </p>
          ) : null}

          <p className="text-center text-sm text-slate-400">
            Already have an account?{' '}
            <Link to="/login" className="font-medium text-accent hover:text-accent2">
              Sign in
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}
