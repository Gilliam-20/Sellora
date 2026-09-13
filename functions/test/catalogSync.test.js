const test = require("node:test");
const assert = require("node:assert");

const {
  flattenCategories,
  normalizeCategoryNode,
  mapSummary,
  buildAttributes,
} = require("../lib/catalogSync");
const { variantAttributes, splitCjKey } = require("../lib/cjApi");

test("normalizeCategoryNode", async (t) => {
  await t.test("reads CJ's first-level key naming", () => {
    assert.deepStrictEqual(
        normalizeCategoryNode({
          categoryFirstId: "1",
          categoryFirstName: "Electronics",
          categoryFirstList: [{ categorySecondId: "2" }],
        }),
        { id: "1", name: "Electronics", children: [{ categorySecondId: "2" }] },
    );
  });

  await t.test("reads the third level, which nests nothing", () => {
    assert.deepStrictEqual(
        normalizeCategoryNode({ categoryId: "9", categoryName: "Cables" }),
        { id: "9", name: "Cables", children: [] },
    );
  });

  await t.test("tolerates a plain id/name shape", () => {
    const node = normalizeCategoryNode({ id: "7", name: "Home", children: [] });
    assert.strictEqual(node.id, "7");
    assert.strictEqual(node.name, "Home");
  });

  await t.test("rejects a node missing an id or a name", () => {
    assert.strictEqual(normalizeCategoryNode({ categoryFirstName: "x" }), null);
    assert.strictEqual(normalizeCategoryNode({ categoryFirstId: "1" }), null);
    assert.strictEqual(normalizeCategoryNode(null), null);
    assert.strictEqual(normalizeCategoryNode("nope"), null);
  });

  await t.test("coerces numeric ids to strings for use as document ids", () => {
    assert.strictEqual(
        normalizeCategoryNode({ categoryId: 42, categoryName: "N" }).id, "42");
  });
});

test("flattenCategories", async (t) => {
  const tree = [{
    categoryFirstId: "1",
    categoryFirstName: "Electronics",
    categoryFirstList: [{
      categorySecondId: "1-1",
      categorySecondName: "Audio",
      categorySecondList: [
        { categoryId: "1-1-1", categoryName: "Earbuds" },
      ],
    }],
  }];

  await t.test("flattens three levels with parent links and depth", () => {
    assert.deepStrictEqual(flattenCategories(tree), [
      { id: "1", name: "Electronics", parentId: "", level: 0 },
      { id: "1-1", name: "Audio", parentId: "1", level: 1 },
      { id: "1-1-1", name: "Earbuds", parentId: "1-1", level: 2 },
    ]);
  });

  await t.test("skips unusable nodes but keeps their usable siblings", () => {
    const rows = flattenCategories([{ junk: true }, ...tree]);
    assert.strictEqual(rows.length, 3);
    assert.strictEqual(rows[0].id, "1");
  });

  await t.test("returns empty for a non-array, rather than throwing", () => {
    assert.deepStrictEqual(flattenCategories(null), []);
    assert.deepStrictEqual(flattenCategories({}), []);
  });
});

test("mapSummary", async (t) => {
  const config = { assumedStock: 999 };
  const cjProduct = {
    id: 123,
    sku: "SKU-1",
    name: "Wireless Earbuds",
    image: "https://cdn/img.jpg",
    supplierPriceUsd: 10,
    retailPriceUsd: 16.45,
    categoryId: "1-1-1",
    categoryName: "Earbuds",
  };

  await t.test("writes the fields ProductModel.fromMap reads", () => {
    const doc = mapSummary(cjProduct, config);
    assert.strictEqual(doc.title, "Wireless Earbuds");
    assert.strictEqual(doc.thumbnailUrl, "https://cdn/img.jpg");
    assert.strictEqual(doc.priceMin, 16.45);
    assert.strictEqual(doc.primaryCategoryId, "1-1-1");
    assert.strictEqual(doc.stockAvailable, 999);
    assert.strictEqual(doc.isActive, true);
    assert.strictEqual(doc.cjProductId, "123");
  });

  await t.test("carries no markdown, so no sale badge is rendered", () => {
    // calculateSalePercentage returns null unless salePrice is both > 0 and
    // below price, so compareAtPriceMin must stay 0 for an undiscounted item.
    assert.strictEqual(mapSummary(cjProduct, config).compareAtPriceMin, 0);
  });

  await t.test("never writes the review-owned rating aggregate", () => {
    const doc = mapSummary(cjProduct, config);
    for (const field of ["ratingAvg", "ratingCount", "ratingBreakdown"]) {
      assert.ok(!(field in doc), `${field} must be left to the review functions`);
    }
  });

  await t.test("defaults missing CJ fields instead of writing undefined", () => {
    const doc = mapSummary({ id: "9" }, config);
    assert.strictEqual(doc.title, "");
    assert.strictEqual(doc.priceMin, 0);
    assert.strictEqual(doc.primaryCategoryId, "");
    for (const value of Object.values(doc)) {
      assert.notStrictEqual(value, undefined, "Firestore rejects undefined");
    }
  });
});

test("variantAttributes", async (t) => {
  await t.test("zips values against the product's attribute names", () => {
    assert.deepStrictEqual(
        variantAttributes("Black-XL", ["Color", "Size"]),
        { Color: "Black", Size: "XL" });
  });

  await t.test("handles a single-attribute product", () => {
    assert.deepStrictEqual(
        variantAttributes("Red", ["Color"]), { Color: "Red" });
  });

  await t.test("falls back when a value itself contains a hyphen", () => {
    // "Navy-Blue-XL" splits into 3 against 2 names - the pairing would be
    // wrong, so the whole key becomes one selectable option instead.
    assert.deepStrictEqual(
        variantAttributes("Navy-Blue-XL", ["Color", "Size"]),
        { Option: "Navy-Blue-XL" });
  });

  await t.test("falls back when CJ sends no attribute names at all", () => {
    assert.deepStrictEqual(
        variantAttributes("Black-XL", []), { Option: "Black-XL" });
  });

  await t.test("returns empty for a variant with no key", () => {
    assert.deepStrictEqual(variantAttributes("", ["Color"]), {});
    assert.deepStrictEqual(variantAttributes(null, ["Color"]), {});
  });

  await t.test("splitCjKey trims and drops empties", () => {
    assert.deepStrictEqual(splitCjKey(" Color - Size "), ["Color", "Size"]);
    assert.deepStrictEqual(splitCjKey("A--B"), ["A", "B"]);
    assert.deepStrictEqual(splitCjKey(""), []);
  });
});

test("buildAttributes", async (t) => {
  await t.test("collects the picker's rows from the variants", () => {
    assert.deepStrictEqual(buildAttributes([
      { AttributeValues: { Color: "Black", Size: "S" } },
      { AttributeValues: { Color: "Black", Size: "M" } },
      { AttributeValues: { Color: "White", Size: "S" } },
    ]), [
      { Name: "Color", Values: ["Black", "White"] },
      { Name: "Size", Values: ["S", "M"] },
    ]);
  });

  await t.test("always emits a Values array, never a missing key", () => {
    // ProductAttributeModel.fromJson used to throw on a missing Values.
    for (const row of buildAttributes([{ AttributeValues: { A: "1" } }])) {
      assert.ok(Array.isArray(row.Values));
    }
  });

  await t.test("ignores variants carrying no attributes", () => {
    assert.deepStrictEqual(buildAttributes([{}, { AttributeValues: {} }]), []);
  });

  await t.test("skips empty values rather than offering a blank choice", () => {
    assert.deepStrictEqual(
        buildAttributes([{ AttributeValues: { Color: "", Size: "M" } }]),
        [{ Name: "Size", Values: ["M"] }]);
  });
});
