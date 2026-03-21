#!/usr/bin/env node
/**
 * Convert Rhino .3dm to glb using rhino3dm WASM render meshes.
 */

const fs = require("fs");
const path = require("path");
const rhino3dm = require("rhino3dm");
const { Document, NodeIO } = require("@gltf-transform/core");

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
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

    // Rhino triangles are often encoded with c == d.
    if (d !== c) {
      indices.push(a, c, d);
      tris += 1;
    }
  }

  return { addedVerts: vCount, addedTris: tris };
}

async function convert3dmToGlb(inputPath, outputPath) {
  const rhino = await rhino3dm();
  const fileBytes = fs.readFileSync(inputPath);
  const safeBytes = new Uint8Array(fileBytes);
  let model = null;
  try {
    model = rhino.File3dm.fromByteArray(safeBytes);
  } catch (_err) {
    model = rhino.File3dm.decode(safeBytes);
  }
  if (!model) {
    throw new Error(`Failed to read 3dm: ${inputPath}`);
  }

  const positions = [];
  const indices = [];
  let objectCount = 0;
  let meshObjectCount = 0;
  let brepFaceMeshCount = 0;
  let triCount = 0;

  const objects = model.objects();
  const count = asInt(objects.count);
  objectCount = count;

  for (let i = 0; i < count; i++) {
    const object = objects.get(i);
    if (!object) continue;
    const geometry = object.geometry();
    if (!geometry) continue;
    const typeName = geometry.constructor ? geometry.constructor.name : "";

    if (typeName === "Mesh") {
      const added = pushMeshGeometry(geometry, positions, indices);
      if (added.addedVerts > 0) {
        meshObjectCount += 1;
        triCount += added.addedTris;
      }
      continue;
    }

    if (typeName === "Brep") {
      const faces = geometry.faces();
      const faceCount = asInt(faces.count);
      for (let j = 0; j < faceCount; j++) {
        const face = faces.get(j);
        if (!face) continue;
        const renderMesh = face.getMesh(rhino.MeshType.Render);
        const added = pushMeshGeometry(renderMesh, positions, indices);
        if (added.addedVerts > 0) {
          brepFaceMeshCount += 1;
          triCount += added.addedTris;
        }
      }
    }
  }

  if (indices.length === 0 || positions.length === 0) {
    throw new Error(`No triangulated mesh data found in ${inputPath}`);
  }

  const doc = new Document();
  const buffer = doc.createBuffer("buffer");
  const scene = doc.createScene("Scene");
  const node = doc.createNode(path.basename(inputPath, path.extname(inputPath)));
  const mesh = doc.createMesh("DistrictMesh");
  const prim = doc.createPrimitive();

  const positionAccessor = doc
    .createAccessor("positions")
    .setType("VEC3")
    .setArray(new Float32Array(positions))
    .setBuffer(buffer);

  let maxIndex = 0;
  for (let i = 0; i < indices.length; i++) {
    if (indices[i] > maxIndex) {
      maxIndex = indices[i];
    }
  }
  const indexArray =
    maxIndex > 65535 ? new Uint32Array(indices) : new Uint16Array(indices);
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

  ensureDirForFile(outputPath);
  const io = new NodeIO();
  await io.write(outputPath, doc);

  return {
    objectCount,
    meshObjectCount,
    brepFaceMeshCount,
    vertexCount: positions.length / 3,
    triangleCount: triCount,
    outputPath,
  };
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error("Usage: node convert_3dm_to_glb.js <input.3dm> <output.glb>");
    process.exit(2);
  }
  const inputPath = path.resolve(args[0]);
  const outputPath = path.resolve(args[1]);
  if (!fs.existsSync(inputPath)) {
    console.error(`Input not found: ${inputPath}`);
    process.exit(2);
  }

  const started = Date.now();
  const result = await convert3dmToGlb(inputPath, outputPath);
  const elapsedMs = Date.now() - started;
  console.log(
    JSON.stringify(
      {
        type: "convert_3dm_to_glb",
        inputPath,
        ...result,
        elapsedMs,
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
