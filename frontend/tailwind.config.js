/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#050505',
        panel: '#0A0A0C',
        panel2: '#16161A',
        border: '#222225',
        accent: '#0050FF',
        accent2: '#00D6FF',
        green: '#0ecb81',
        red: '#f6465d'
      },
      boxShadow: {
        glow: '0 0 0 1px rgba(0,214,255,0.15), 0 20px 60px rgba(0,0,0,0.5)'
      }
    }
  },
  plugins: []
};
