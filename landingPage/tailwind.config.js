/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy: {
          950: '#060d1f',
          900: '#0d1b3e',
          800: '#112254',
          700: '#1a3272',
        },
        teal: {
          DEFAULT: '#00e5c0',
          dark:    '#00a88a',
          dim:     '#00876e',
        },
      },
      fontFamily: {
        display: ['"Sora"', 'sans-serif'],
        body:    ['"DM Sans"', 'sans-serif'],
        mono:    ['"JetBrains Mono"', 'monospace'],
      },
      animation: {
        ticker:  'ticker 22s linear infinite',
        fadeUp:  'fadeUp 0.7s ease forwards',
        bounce2: 'bounce2 2s ease-in-out infinite',
      },
      keyframes: {
        ticker:  { '0%': { transform: 'translateX(0)' }, '100%': { transform: 'translateX(-50%)' } },
        fadeUp:  { from: { opacity: 0, transform: 'translateY(28px)' }, to: { opacity: 1, transform: 'translateY(0)' } },
        bounce2: { '0%,100%': { transform: 'translateY(0)' }, '50%': { transform: 'translateY(8px)' } },
      },
    },
  },
  plugins: [],
}
