/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#07111f',
        panel: '#0c1728',
        panel2: '#101b2e',
        border: '#1f2a3d',
        accent: '#f0b90b',
        accent2: '#fcd535',
        green: '#0ecb81',
        red: '#f6465d'
      },
      boxShadow: {
        glow: '0 0 0 1px rgba(240,185,11,0.15), 0 20px 60px rgba(0,0,0,0.35)'
      }
    }
  },
  plugins: []
};
