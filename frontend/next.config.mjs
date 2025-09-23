/** @type {import('next').NextConfig} */
const isProduction = process.env.NODE_ENV === 'production';

const nextConfig = {
  reactStrictMode: true,
  experimental: {
    typedRoutes: true
  },
  ...(isProduction ? { output: 'export' } : {})
};

export default nextConfig;
