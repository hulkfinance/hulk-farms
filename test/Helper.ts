import { expect } from "chai";
import { ethers, network } from "hardhat";
import { getCurrentTimestamp } from "hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp";

export function getTimestamp() {
  return getCurrentTimestamp();
}

export async function expectRevert(condition: any, message: string) {
  await expect(condition).to.revertedWith(message);
}

export async function increaseTime(forSeconds: number) {
  await network.provider.send("evm_increaseTime", [forSeconds]);
  await network.provider.send("evm_mine");
}

export async function setNextBlockTimestamp(timestamp: number) {
  await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
  await network.provider.send("evm_mine");
}

export async function mineBlock() {
  await network.provider.send("evm_mine");
}

export async function getCurrentBlockNumber(): Promise<number> {
  return ethers.provider.getBlockNumber();
}
