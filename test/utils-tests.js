const chai = require("chai");
const { ethers, waffle } = require("hardhat");
const should = require("should");
const { returnVestingSchedule } = require("../utils/utils");
chai.use(waffle.solidity);
const { expect, assert } = chai;

describe("utils", function () {
  let owner, alice, bob, charlie, token, utils, dave;
  const NULL_ADDRESS = `0x${"0".repeat(40)}`;

  beforeEach(async () => {
    [owner, alice, bob, charlie, dave] = await ethers.getSigners();
    Contract = await ethers.getContractFactory("MockDeltaToken");
    token = await Contract.deploy("delta", "delta");
    Contract = await ethers.getContractFactory("Utils");
    utils = await Contract.deploy(token.address);
  })

  it("should batch transfer", async function () {
    const amount = (1 * 1e18).toString();

	try {
		await utils.batchTokenTransfer([alice.address, bob.address], [amount, amount])
		should.fail("no error was thrown when it should have been");
	  } catch (e) {
		assert.equal(
		  e.message,
		  "VM Exception while processing transaction: revert ERC20: transfer amount exceeds allowance"
		);
	  }


	const balanceOfOwner = await token.balanceOf(owner.address);
    await token.approve(utils.address, balanceOfOwner);


	await utils.batchTokenTransfer([alice.address, bob.address], [amount, amount])
	
	const aliceBalanceAfter = await token.balanceOf(alice.address)
	const bobBalanceAfter = await token.balanceOf(bob.address)

	assert.equal(aliceBalanceAfter.toString(), amount)
	assert.equal(bobBalanceAfter.toString(), amount)

  })
  it("should load test batch", async function () {
	const amount = (1 * 1e18).toString();

	const balanceOfOwner = await token.balanceOf(owner.address);
    await token.approve(utils.address, balanceOfOwner);


	await utils.batchTokenTransfer(Array(300).fill(alice.address), Array(300).fill(amount))
  })
})