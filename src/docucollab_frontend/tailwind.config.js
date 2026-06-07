/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
        },
        icp: {
          purple: '#7b3fe4',
          violet: '#9b4bf0',
          pink: '#e0359a',
          magenta: '#ec4899',
          cyan: '#29c5f6',
          blue: '#3b82f6',
        },
        dc: {
          bg0: '#06060c',
          bg1: '#0a0a14',
          bg2: '#0e0e1b',
          green: '#19e08a',
          amber: '#f5b544',
          red: '#fb6a6a',
        },
      },
      fontFamily: {
        display: ['Space Grotesk', 'system-ui', 'sans-serif'],
        body: ['Manrope', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
      borderRadius: {
        sm2: '10px',
        md2: '14px',
        lg2: '20px',
        xl2: '28px',
      },
    },
  },
  plugins: [],
};
