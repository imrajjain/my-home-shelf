import { test } from "node:test";
import assert from "node:assert/strict";
import { canSee, shareable, normalizeUsername, type Relation, type Visibility } from "../src/visibility";

test("who sees what", () => {
  const cases: [Relation, Visibility | undefined, boolean][] = [
    ["owner", "private", true], ["owner", undefined, true],
    ["friend", "private", false], ["friend", "friends", true], ["friend", "public", true],
    ["follower", "friends", false], ["follower", "public", true],
    ["stranger", "friends", false], ["stranger", "public", true],
    ["anonymous", "private", false], ["anonymous", "friends", false], ["anonymous", "public", true],
    ["friend", undefined, false], ["anonymous", undefined, false],
  ];
  for (const [relation, visibility, expected] of cases) {
    assert.equal(canSee(relation, visibility), expected, `${relation} / ${visibility}`);
  }
});

test("shared copies hide notes, ratings, progress and private extras unless switched on", () => {
  const record = { id: "x", title: "Dune", notes: "loved it", rating: 5, progress: 0.4, extra: { goodreadsID: "1" } };
  assert.deepEqual(shareable(record, undefined), { id: "x", title: "Dune", notes: "", rating: 0, progress: 0, extra: {} });
  assert.deepEqual(shareable(record, { notes: true, rating: true }), { id: "x", title: "Dune", notes: "loved it", rating: 5, progress: 0, extra: {} });
});

test("usernames", () => {
  assert.equal(normalizeUsername("@Raj_Jain"), "raj_jain");
  assert.equal(normalizeUsername("ab"), null);
  assert.equal(normalizeUsername("has space"), null);
  assert.equal(normalizeUsername("admin"), null);
  assert.equal(normalizeUsername("x".repeat(21)), null);
});
