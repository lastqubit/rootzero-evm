import { defineConfig } from "hardhat/config";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";

export default defineConfig({
  plugins: [hardhatMocha],
  solidity: {
    version: "0.8.35",
    settings: {
      // Use the same IR pipeline for development, tests, and gas benchmarks.
      viaIR: true,
      // The codec uses MCOPY, making Cancun the oldest supported EVM target.
      // Pinning it avoids silently adopting newer opcodes with compiler upgrades.
      evmVersion: "cancun",
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // TestHost intentionally composes nearly every endpoint into one integration
    // fixture; normal hosts inherit only the endpoints they use.
    default: {
      type: "edr-simulated",
      chainType: "l1",
      allowUnlimitedContractSize: true,
    },
  },
  test: {
    mocha: {
      require: ["./test/helpers/matchers.ts"],
    },
  },
});
