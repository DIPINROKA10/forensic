/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The Docker image (see Dockerfile) needs the self-contained server output,
  // so it sets NEXT_OUTPUT=standalone at build time. Vercel and Netlify both
  // expect the default output and must not get `standalone`.
  ...(process.env.NEXT_OUTPUT === "standalone" ? { output: "standalone" } : {}),
};

module.exports = nextConfig;
