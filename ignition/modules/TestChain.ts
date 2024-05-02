import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const JAN_1ST_2030 = 1893456000;
const ONE_GWEI: bigint = 1_000_000_000n;
const USDT_ADDRESS = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd";

const TestChainModule = buildModule("TestChainModule", (m) => {
  const usdtAddress = m.getParameter("USDT", USDT_ADDRESS);
  
  const testChain = m.contract("TestChain", [usdtAddress]);

  return { testChain };
});

export default TestChainModule;
