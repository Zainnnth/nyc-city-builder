#!/usr/bin/env node
/**
 * Extract per-building metadata (and optional per-building glb files) from a district .3dm.
 */

const fs = require("fs");
const path = require("path");
const rhino3dm = require("rhino3dm");
const { Document, NodeIO } = require("@gltf-transform/core");

function parseArgs(argv) {
  const out = {
    input: "",
    districtCode: "",
    districtId: "outer_borough_mix",
    styleProfile: "default_mixed",
    outCatalog: "",
    outGlbDir: "",
    maxBuildings: 0,
    writeGlb: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--input") out.input = argv[++i] || "";
    else if (a === "--district-code") out.districtCode = argv[++i] || "";
    else if (a === "--district-id") out.districtId = argv[++i] || out.districtId;
    else if (a === "--style-profile") out.styleProfile = argv[++i] || out.styleProfile;
    else if (a === "--out-catalog") out.outCatalog = argv[++i] || "";
    else if (a === "--out-glb-dir") out.outGlbDir = argv[++i] || "";
    else if (a === "--max-buildings") out.maxBuildings = Number.parseInt(argv[++i] || "0", 10) || 0;
    else if (a === "--write-glb") out.writeGlb = true;
  }
  return out;
}

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function asInt(value) {
  return Number.parseInt(String(value), 10);
}

function pushMeshGeometry(mesh, positions, indices) {
  if (!mesh) return { addedVerts: 0, addedTris: 0 };
  const vertices = mesh.vertices();
  const faces = mesh.faces();
  const baseIndex = positions.length / 3;
  const vCount = asInt(vertices.count);
  const fCount = asInt(faces.count);

  for (let i = 0; i < vCount; i++) {
    const v = vertices.get(i);
    if (!v || v.length < 3) continue;
    positions.push(Number(v[0]), Number(v[1]), Number(v[2]));
  }

  let tris = 0;
  for (let i = 0; i < fCount; i++) {
    const f = faces.get(i);
    if (!f || f.length < 4) continue;
    const a = baseIndex + asInt(f[0]);
    const b = baseIndex + asInt(f[1]);
    const c = baseIndex + asInt(f[2]);
    const d = baseIndex + asInt(f[3]);
    indices.push(a, b, c);
    tris += 1;
    if (d !== c) {
      indices.push(a, c, d);
      tris += 1;
    }
  }
  return { addedVerts: vCount, addedTris: tris };
}

function boundsFromPositions(positions) {
  if (!positions.length) return null;
  let minX = positions[0], minY = positions[1], minZ = positions[2];
  let maxX = positions[0], maxY = positions[1], maxZ = positions[2];
  for (let i = 3; i < positions.length; i += 3) {
    const x = positions[i + 0];
    const y = positions[i + 1];
    const z = positions[i + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  return {
    min: [minX, minY, minZ],
    max: [maxX, maxY, maxZ],
    center: [(minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5],
    size: [maxX - minX, maxY - minY, maxZ - minZ],
  };
}

async function writeBuildingGlb(outPath, positions, indices, nodeName) {
  const doc = new Document();
  const buffer = doc.createBuffer("buffer");
  const scene = doc.createScene("Scene");
  const node = doc.createNode(nodeName);
  const mesh = doc.createMesh("BuildingMesh");
  const prim = doc.createPrimitive();

  const positionAccessor = doc
    .createAccessor("positions")
    .setType("VEC3")
    .setArray(new Float32Array(positions))
    .setBuffer(buffer);

  let maxIndex = 0;
  for (let i = 0; i < indices.length; i++) if (indices[i] > maxIndex) maxIndex = indices[i];
  const indexArray = maxIndex > 65535 ? new Uint32Array(indices) : new Uint16Array(indices);
  const indexAccessor = doc
    .createAccessor("indices")
    .setType("SCALAR")
    .setArray(indexArray)
    .setBuffer(buffer);

  prim.setAttribute("POSITION", positionAccessor);
  prim.setIndices(indexAccessor);
  mesh.addPrimitive(prim);
  node.setMesh(mesh);
  scene.addChild(node);

  ensureDirForFile(outPath);
  const io = new NodeIO();
  await io.write(outPath, doc);
}

async function extractBuildings(opts) {
  const rhino = await rhino3dm();
  const bytes = new Uint8Array(fs.readFileSync(opts.input));
  let model = null;
  try {
    model = rhino.File3dm.fromByteArray(bytes);
  } catch (_err) {
    model = rhino.File3dm.decode(bytes);
  }
  if (!model) throw new Error(`Failed to read 3dm: ${opts.input}`);

  const objects = model.objects();
  const totalObjects = asInt(objects.count);
  const entries = [];
  let scannedBreps = 0;
  let skippedNoMesh = 0;
  let writtenGlb = 0;

  for (let i = 0; i < totalObjects; i++) {
    if (opts.maxBuildings > 0 && entries.length >= opts.maxBuildings) break;
    const object = objects.get(i);
    if (!object) continue;
    const geometry = object.geometry();
    if (!geometry) continue;
    const typeName = geometry.constructor ? geometry.constructor.name : "";
    if (typeName !== "Brep") continue;
    scannedBreps += 1;

    const positions = [];
    const indices = [];
    const faces = geometry.faces();
    const faceCount = asInt(faces.count);
    let triCount = 0;
    for (let j = 0; j < faceCount; j++) {
      const face = faces.get(j);
      if (!face) continue;
      const mesh = face.getMesh(rhino.MeshType.Render);
      const added = pushMeshGeometry(mesh, positions, indices);
      triCount += added.addedTris;
    }
    if (!positions.length || !indices.length || triCount <= 0) {
      skippedNoMesh += 1;
      continue;
    }

    const bounds = boundsFromPositions(positions);
    if (!bounds) continue;
    const districtCode = opts.districtCode || path.basename(opts.input, path.extname(opts.input)).toUpperCase();
    const buildingId = `${districtCode}_b${String(entries.length + 1).padStart(5, "0")}`;

    let glbPath = "";
    if (opts.writeGlb && opts.outGlbDir) {
      glbPath = path.join(opts.outGlbDir, `${buildingId}.glb`).replace(/\\/g, "/");
      await writeBuildingGlb(glbPath, positions, indices, buildingId);
      writtenGlb += 1;
    }

    entries.push({
      building_id: buildingId,
      source_object_index: i,
      district_code: districtCode,
      district_id: opts.districtId,
      style_profile: opts.styleProfile,
      height_m: Number(bounds.size[2].toFixed(3)),
      tri_count: triCount,
      vertex_count: positions.length / 3,
      centroid_xyz: bounds.center,
      bounds_min_xyz: bounds.min,
      bounds_max_xyz: bounds.max,
      glb_path: glbPath,
    });
  }

  const payload = {
    source_file: opts.input.replace(/\\/g, "/"),
    district_code: opts.districtCode || path.basename(opts.input, path.extname(opts.input)).toUpperCase(),
    district_id: opts.districtId,
    style_profile: opts.styleProfile,
    generated_utc: new Date().toISOString(),
    stats: {
      total_objects: totalObjects,
      scanned_breps: scannedBreps,
      extracted_buildings: entries.length,
      skipped_no_mesh: skippedNoMesh,
      written_glb: writtenGlb,
    },
    entries,
  };

  ensureDirForFile(opts.outCatalog);
  fs.writeFileSync(opts.outCatalog, JSON.stringify(payload, null, 2), "utf8");
  return payload;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.input || !opts.outCatalog) {
    console.error("Usage: node extract_buildings_from_3dm.js --input <file.3dm> --out-catalog <catalog.json> [--district-code MN01] [--district-id financial_district] [--style-profile historic_core_tower_mix] [--max-buildings 200] [--write-glb --out-glb-dir assets/buildings/nyc3d/buildings/MN01]");
    process.exit(2);
  }
  if (opts.writeGlb && !opts.outGlbDir) {
    console.error("--write-glb requires --out-glb-dir");
    process.exit(2);
  }
  if (opts.outGlbDir) ensureDir(opts.outGlbDir);

  const started = Date.now();
  const payload = await extractBuildings(opts);
  const elapsedMs = Date.now() - started;
  console.log(
    JSON.stringify(
      {
        type: "extract_buildings_from_3dm",
        input: opts.input,
        outCatalog: opts.outCatalog,
        extracted_buildings: payload.stats.extracted_buildings,
        written_glb: payload.stats.written_glb,
        elapsedMs,
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
