import { ethers, upgrades, network } from "hardhat";
import hre from "hardhat";

async function main() {
    console.log('Deploying...');
    const V1Contract = await ethers.getContractFactory('TestChainUpgradable');
    const v1Contract = await upgrades.deployProxy(V1Contract, [], {
        initializer: 'initialize'
    });

    
    await v1Contract.deployed();
    console.log('V1 Contract deployed: ', v1Contract.address);
    
    // const V2Contract = await ethers.getContractFactory("TestChainUpgradable");
    // let upgrade = await upgrades.upgradeProxy('UPGRADEABLE_PROXY', V2Contract, {
        
    // });

    // await hre.run("verify:verify", {

    // })
}

main().catch(err => {
    console.error(err);
    process.exitCode = 1;
})