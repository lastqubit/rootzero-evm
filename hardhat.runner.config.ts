import { defineConfig } from "hardhat/config";
import config from "./hardhat.config.js";

// Reproduce the shared command-runner measurements without changing the
// repository's default compiler or its Cancun compatibility target.
export default defineConfig({
  ...config,
  solidity: {
    version: "0.8.33",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: { enabled: true, runs: 200 },
    },
  },
});
