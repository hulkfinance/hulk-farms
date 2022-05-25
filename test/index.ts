import chai from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { solidity } from "ethereum-waffle";
import UniswapV2FactoryArtifacts from "@uniswap/v2-core/build/UniswapV2Factory.json";
import UniswapV2PairArtifacts from "@uniswap/v2-core/build/UniswapV2Pair.json";
import WETH9Artifacts from "@uniswap/v2-periphery/build/WETH9.json";
// import assert from "assert";
// import { mineBlock } from "./Helper";

const { AddressZero } = ethers.constants;

chai.use(solidity);

// describe("Greeter", function () {
//   it("Should return the new greeting once it's changed", async function () {
//     const Greeter = await ethers.getContractFactory("Greeter");
//     const greeter = await Greeter.deploy("Hello, world!");
//     await greeter.deployed();
//
//     expect(await greeter.greet()).to.equal("Hello, world!");
//
//     const setGreetingTx = await greeter.setGreeting("Hola, mundo!");
//
//     // wait until the transaction is mined
//     await setGreetingTx.wait();
//
//     expect(await greeter.greet()).to.equal("Hola, mundo!");
//   });
// });
describe("HULKMasterChef", function () {
  // создаем пермнную для аккаунтов
  let accounts: Signer[];

  // создаем переменные для пользователей-отправителей
  let OWNER_SIGNER: any;
  let DEV_SIGNER: any;
  let ALICE_SIGNER: any;

  let OWNER: any;
  // eslint-disable-next-line no-unused-vars
  let DEV: any;
  let ALICE: any;

  // контракт фермы
  let farm: any;
  // контракт токена
  let hulkToken: any;
  // let voucher: any;

  // контракт фабрики
  let factory: any;

  // контракты токенов
  let weth: any;
  let usd: any;

  const pancakeRouterAddress: string =
    "0x083f812BF6b51477Afa58033a4B8a2cA884293e5";

  // максимальное количество токенов
  // const MAX_SUPPLY = "10000000000000000000000000000";

  // функция для получения адреса пары
  const getPairAddress: any = async function (
    tokenA: string,
    tokenB: string
  ): Promise<Contract> {
    const UniswapV2Pair: any = await ethers.getContractFactory(
      UniswapV2PairArtifacts.abi,
      UniswapV2PairArtifacts.bytecode
    );

    return UniswapV2Pair.attach(String(await factory.getPair(tokenA, tokenB)));
  };
  before("config", async () => {
    // сетим аккаунты
    accounts = await ethers.getSigners();

    // сетим для аккаунтов-отправителей
    OWNER_SIGNER = accounts[0];
    DEV_SIGNER = accounts[1];
    ALICE_SIGNER = accounts[2];
    // сетим адреса аккаунтов-отправителей
    OWNER = await OWNER_SIGNER.getAddress();
    DEV = await DEV_SIGNER.getAddress();
    ALICE = await ALICE_SIGNER.getAddress();

    // создаем инстансы контрактов
    const HULKToken = await ethers.getContractFactory("HULKToken");
    const MasterChef = await ethers.getContractFactory("HULKMasterChef");
    const BEP20Mock = await ethers.getContractFactory("BEP20Mock");
    const UniswapV2Factory = await ethers.getContractFactory(
      UniswapV2FactoryArtifacts.abi,
      UniswapV2FactoryArtifacts.bytecode
    );
    const WETH9 = await ethers.getContractFactory(
      WETH9Artifacts.abi,
      WETH9Artifacts.bytecode
    );
    // const UniswapV2Pair = await ethers.getContractFactory(
    //   UniswapV2PairArtifacts.abi,
    //   UniswapV2PairArtifacts.bytecode
    // );

    factory = await UniswapV2Factory.deploy(OWNER);
    await factory.deployed();

    weth = await WETH9.deploy();
    await weth.deployed();

    hulkToken = await HULKToken.deploy(pancakeRouterAddress);
    await hulkToken.deployed();

    const MINTER_ROLE = await hulkToken.MINTER_ROLE();

    usd = await BEP20Mock.deploy();
    await usd.deployed();

    const hulkPerBlock = "1000000";
    farm = await MasterChef.deploy(hulkToken.address, hulkPerBlock);
    await farm.deployed();

    await factory.createPair(weth.address, usd.address);
    const WETH_USD: Contract = await getPairAddress(weth.address, usd.address);

    console.log(`Pair: ${WETH_USD.address}`);

    await usd.mint(WETH_USD.address, "5000000000000000000");
    await weth.deposit({ value: "100000000000000" });
    await weth.transfer(WETH_USD.address, "100000000000000");

    await WETH_USD.mint(ALICE);

    console.log(await WETH_USD.balanceOf(AddressZero));
    console.log(await WETH_USD.balanceOf(ALICE));
    console.log(await WETH_USD.balanceOf(OWNER));

    await factory.createPair(weth.address, hulkToken.address);
    const WETH_UM: Contract = await getPairAddress(
      weth.address,
      hulkToken.address
    );

    console.log(`Pair: ${WETH_UM.address}`);

    await hulkToken.grantRole(MINTER_ROLE, OWNER);
    await hulkToken.mint(WETH_UM.address, "5000000000000000");
    await weth.deposit({ value: "1000000000000000" });
    await weth.transfer(WETH_UM.address, "1000000000000000");

    await WETH_UM.mint(ALICE);

    console.log(await WETH_UM.balanceOf(AddressZero));
    console.log(await WETH_UM.balanceOf(ALICE));
    console.log(await WETH_UM.balanceOf(OWNER));

    await hulkToken.grantRole(MINTER_ROLE, farm.address);
  });
  describe.only("success cases", () => {
    it("#add", async () => {
      const WETH_USD: Contract = await getPairAddress(
        weth.address,
        usd.address
      );
      await farm.add(100, WETH_USD.address, true);

      const WETH_UM: Contract = await getPairAddress(
        weth.address,
        hulkToken.address
      );
      await farm.add(150, WETH_UM.address, true);
    });

    it("#set", async () => {
      await farm.set(0, 99, true);
      await farm.set(0, 101, false);
      await farm.set(0, 100, true);
    });

    // it("#setRewardMultiplier", async () => {
    //   await farm.setRewardMultiplier(10);
    //   assert.equal(
    //     Number(await farm.rewardMultiplier()),
    //     10,
    //     "Reward multiplier 10"
    //   );
    //   await farm.setRewardMultiplier(1);
    //   assert.equal(
    //     Number(await farm.rewardMultiplier()),
    //     1,
    //     "Reward multiplier 1"
    //   );
    // });

    // it("#deposit", async () => {
    //   const WETH_USD: Contract = await getPairAddress(
    //     weth.address,
    //     usd.address
    //   );
    //   await WETH_USD.connect(ALICE_SIGNER).approve(
    //     farm.address,
    //     "22360679774996896"
    //   );
    //   await farm.connect(ALICE_SIGNER).deposit(0, "22360679774996896");
    //   console.log(await farm.pendingReward(0, ALICE));
    //   await mineBlock();
    //   console.log(await farm.pendingReward(0, ALICE));
    //   await mineBlock();
    //   console.log(await farm.pendingReward(0, ALICE));
    //
    //   const WETH_UM: Contract = await getPairAddress(
    //     weth.address,
    //     hulkToken.address
    //   );
    //   await WETH_UM.connect(ALICE_SIGNER).approve(
    //     farm.address,
    //     "2236067977498789"
    //   );
    //   await farm.connect(ALICE_SIGNER).deposit(1, "2236067977498789");
    //   console.log(await farm.pendingReward(1, ALICE));
    //   await mineBlock();
    //   console.log(await farm.pendingReward(1, ALICE));
    //   await mineBlock();
    //   console.log(await farm.pendingReward(1, ALICE));
    // });

    // it("claim through multicall", async () => {
    //   await mineBlock();
    //   console.log(`Reward Alice pool 0: ${await farm.pendingReward(0, ALICE)}`);
    //   console.log(`Reward Alice pool 1: ${await farm.pendingReward(1, ALICE)}`);
    //
    //   await farm
    //     .connect(ALICE_SIGNER)
    //     .multicall([
    //       farm.interface.encodeFunctionData("deposit", [0, 0]),
    //       farm.interface.encodeFunctionData("deposit", [1, 0]),
    //     ]);
    //
    //   assert.equal(
    //     Number(await farm.pendingReward(0, ALICE)),
    //     0,
    //     "Pool reward 0 not zero?"
    //   );
    //   assert.equal(
    //     Number(await farm.pendingReward(1, ALICE)),
    //     0,
    //     "Pool reward 0 not zero?"
    //   );
    //
    //   await mineBlock();
    //   console.log(`Reward Alice pool 0: ${await farm.pendingReward(0, ALICE)}`);
    //   console.log(`Reward Alice pool 1: ${await farm.pendingReward(1, ALICE)}`);
    //
    //   await farm
    //     .connect(ALICE_SIGNER)
    //     .multicall([
    //       farm.interface.encodeFunctionData("deposit", [0, 0]),
    //       farm.interface.encodeFunctionData("deposit", [0, 0]),
    //     ]);
    //
    //   assert.equal(
    //     Number(await farm.pendingReward(0, ALICE)),
    //     0,
    //     "Pool reward 0 not zero?"
    //   );
    // });

    // it("#withdraw", async () => {
    //   const WETH_USD: Contract = await getPairAddress(
    //     weth.address,
    //     usd.address
    //   );
    //
    //   console.log(await farm.pendingReward(0, ALICE));
    //   await farm.connect(ALICE_SIGNER).withdraw(0, "22360679774996896");
    //
    //   console.log(await farm.pendingReward(0, ALICE));
    //   console.log(await WETH_USD.balanceOf(ALICE));
    //   console.log(await hulkToken.balanceOf(ALICE));
    //
    //   const WETH_UM: Contract = await getPairAddress(
    //     weth.address,
    //     hulkToken.address
    //   );
    //
    //   console.log(await farm.pendingReward(1, ALICE));
    //   await farm.connect(ALICE_SIGNER).withdraw(1, "2236067977498789");
    //
    //   console.log(await farm.pendingReward(1, ALICE));
    //   console.log(await WETH_UM.balanceOf(ALICE));
    //   console.log(await hulkToken.balanceOf(ALICE));
    // });
  });
});
