/** Read-only, aggregate fingerprints. No row values or connection secrets leave PostgreSQL. */
const path = require("node:path");
const fs = require("node:fs");
const api = path.resolve(__dirname, "../../api");
require(path.join(api, "node_modules/dotenv")).config({
  path: path.resolve(api, "../../.env"),
  quiet: true,
});
const source = new URL(process.env.DATABASE_URL);
if (
  !["postgres:", "postgresql:"].includes(source.protocol) ||
  !["127.0.0.1", "localhost"].includes(source.hostname)
)
  throw Error("Local source required");
const tables = [
  "pengguna",
  "layanan",
  "loket",
  "jadwal_layanan",
  "penugasan_petugas",
  "tiket_antrean",
  "urutan_antrean_harian",
  "peristiwa_antrean",
  "perangkat_tampilan",
  "sesi_pengguna",
  "notifikasi",
  "dokter",
  "dokter_layanan",
  "jadwal_praktik",
  "slot_praktik",
  "janji_temu",
  "_prisma_migrations",
];
const { Client } = require(path.join(api, "node_modules/pg"));
async function fingerprint(database) {
  const target = new URL(`postgresql://127.0.0.1:5433/${database}`);
  target.username = source.username;
  target.password = source.password;
  const db = new Client({
    connectionString: target.toString(),
    connectionTimeoutMillis: 5000,
  });
  try {
    await db.connect();
    await db.query(
      "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY",
    );
    const actual = (
      await db.query(
        "SELECT current_database() AS db, inet_server_port() AS port",
      )
    ).rows[0];
    if (actual.db !== database || ![5432, 5433].includes(actual.port))
      throw Error("Wrong database");
    const result = {};
    for (const table of tables) {
      result[table] = (
        await db.query(`SELECT count(*)::int AS count,
        md5(coalesce(string_agg(md5(row_to_json(t)::text), '' ORDER BY id), '')) AS hash
        FROM "${table}" t`)
      ).rows[0];
    }
    await db.query("ROLLBACK");
    return result;
  } finally {
    await db.end();
  }
}
(async () => {
  const result = {};
  for (const database of ["capstone_antrean", "capstone_antrean_test"])
    result[database] = await fingerprint(database);
  const destination = process.argv[2];
  if (!destination) throw Error("Explicit output file required");
  const output = path.resolve(destination);
  if (!output.startsWith(path.resolve(__dirname, "..", "build") + path.sep))
    throw Error("Output must stay in client/build");
  fs.writeFileSync(output, JSON.stringify(result, null, 2) + "\n");
  console.log(
    JSON.stringify({
      readOnly: true,
      databases: Object.keys(result),
      tablesPerDatabase: tables.length,
    }),
  );
})().catch((error) => {
  console.error("Fingerprint failed: " + (error.code || error.name));
  process.exitCode = 1;
});
