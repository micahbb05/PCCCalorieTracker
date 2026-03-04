import { defineConfig } from 'vite';

export default defineConfig({
    server: {
        proxy: {
            '/api/nutrislice': {
                target: 'https://pccdining.api.nutrislice.com',
                changeOrigin: true,
                rewrite: (path) => path.replace(/^\/api\/nutrislice/, '')
            }
        }
    }
});
