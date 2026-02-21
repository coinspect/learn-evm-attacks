/**
 * Declarative schema for README.md YAML frontmatter.
 *
 * Each field is described with:
 *   type     – "string" | "number" | "date" | "array" | "objectArray"
 *   required – whether the field must be present (default: true)
 *   items    – for "array": the type of each element ("string" | "number")
 *              for "objectArray": an object mapping keys to their types
 *   min      – for "number": minimum allowed value
 *   default  – value used when the field is missing
 *
 * To update the schema, just edit this object.
 */

const readmeSchema = {
  // Basic information
  title:        { type: "string" },
  description:  { type: "string", required: false },
  type:         { type: "string" },
  network:      { type: "array", items: "string" },
  date:         { type: "date" },
  publishingDate: { type: "date", required: false },

  // Financial impact
  loss_usd:     { type: "number", min: 0, default: 0, required: false },
  returned_usd: { type: "number", min: 0, default: 0, required: false },

  // Classification
  tags:         { type: "array", items: "string" },
  category:     { type: "array", items: "string", required: false },
  subcategory:  { type: "array", items: "string", required: false },

  // Technical details
  vulnerable_contracts: { type: "array", items: "string" },
  tokens_lost:          { type: "array", items: "string", required: false },
  attacker_addresses:   { type: "array", items: "string" },
  malicious_token:      { type: "array", items: "string", required: false },
  attack_block:         { type: "array", items: "number" },
  attack_txs:           { type: "array", items: "string" },

  // Testing and reproduction
  reproduction_command: { type: "string" },

  // Sources and references
  sources: { type: "objectArray", items: { title: "string", url: "string" } },
};

module.exports = { readmeSchema };
