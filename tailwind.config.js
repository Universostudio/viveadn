/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Marca Vive ADN: paleta "ADN Vital"
        adn: {
          verde:    '#00523c',
          oscuro:   '#003828',
          claro:    '#0b7a58',
          oro:      '#f5a623',
          arena:    '#f4f0e6',
          profundo: '#2c3e50',
        },
        alerta: {
          verde:    '#10b981',
          amarillo: '#f59e0b',
          naranja:  '#f97316',
          rojo:     '#ef4444',
        },
      },
      fontFamily: {
        sans:    ['"DM Sans"', 'system-ui', 'sans-serif'],
        display: ['"Plus Jakarta Sans"', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
