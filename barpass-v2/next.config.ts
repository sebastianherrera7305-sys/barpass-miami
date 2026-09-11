import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // sharp ships a platform-specific native binary; bundling it breaks the
  // function at import time (every /api/img request returned 500, including
  // the paths that reject before any work).
  serverExternalPackages: ["sharp"],
};

export default nextConfig;
