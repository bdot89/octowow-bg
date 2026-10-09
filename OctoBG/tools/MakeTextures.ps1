param([Parameter(Mandatory=$true)][string]$OutDir)
# Generates OctoBG's textures as uncompressed 32-bit TGA (power-of-two sizes,
# bottom-left origin). Colour is applied in game with SetVertexColor, which
# multiplies: white parts take the colour, black parts (the outlines of pip
# and badge) stay black, so markers read on any map.

$src = @"
using System;
using System.IO;
public static class Tex {
  // Coverage (alpha) and brightness (0 = black, 1 = white) at a sample point.
  static double Shape(string kind, double x, double y, int w, out double lum) {
    double c = w / 2.0, d = Math.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
    lum = 1;
    switch (kind) {
      case "ring":   return Math.Abs(d - (c - 2.5)) <= 1.25 ? 1 : 0;
      case "disc":   return d <= c - 2.5 ? 1 : 0;
      case "circle": return Math.Abs(d - (c - 3.5)) <= 2.0 ? 1 : 0;
      case "glow":   { double r = d / (c - 1); return r >= 1 ? 0 : Math.Pow(1 - r, 0.6); }
      case "arrow":  return Arrow(x, y, w);
      // pip: white dot with a black rim (class-coloured markers)
      case "pip":    if (d > 15) return 0; lum = d <= 11 ? 1 : 0; return 1;
      // badge: thick white ring between black rims, hollow centre (faction outline)
      case "badge":  if (d > 15.5 || d < 6.5) return 0; lum = (d >= 8.5 && d <= 13) ? 1 : 0; return 1;
      // tri: white triangle pointing up with a black rim; centroid at the texture centre
      case "tri": {
        double k = w / 32.0;
        double ax = 16 * k, ay = 1.5 * k, bx = 3 * k, by = 23.5 * k, cx = 29 * k, cy = 23.5 * k;
        double m = Math.Min(EdgeDist(x, y, ax, ay, bx, by, cx, cy),
                   Math.Min(EdgeDist(x, y, bx, by, cx, cy, ax, ay), EdgeDist(x, y, cx, cy, ax, ay, bx, by)));
        if (m < 0) return 0;
        lum = m > 2.6 * k ? 1 : 0;
        return 1;
      }
    }
    return 0;
  }
  // Distance of p from the line a-b, positive on the side where c lies.
  static double EdgeDist(double px, double py, double ax, double ay, double bx, double by, double cx, double cy) {
    double nx = -(by - ay), ny = bx - ax, len = Math.Sqrt(nx * nx + ny * ny);
    nx /= len; ny /= len;
    double d = (px - ax) * nx + (py - ay) * ny;
    return ((cx - ax) * nx + (cy - ay) * ny) < 0 ? -d : d;
  }
  static bool InTri(double px, double py, double ax, double ay, double bx, double by, double cx, double cy) {
    double d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    double d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    double d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    bool neg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    bool pos = (d1 > 0) || (d2 > 0) || (d3 > 0);
    return !(neg && pos);
  }
  // Arrow head pointing up (top of the image): tip, right wing, notch, left wing.
  // Kept inside the inscribed circle so any rotation stays within the texture.
  static double Arrow(double x, double y, double s) {
    double tx = 0.5 * s, ty = 0.08 * s, rx = 0.8 * s, ry = 0.84 * s, nx = 0.5 * s, ny = 0.64 * s, lx = 0.2 * s, ly = 0.84 * s;
    return (InTri(x, y, tx, ty, rx, ry, nx, ny) || InTri(x, y, tx, ty, nx, ny, lx, ly)) ? 1 : 0;
  }
  public static void Write(string path, string kind, int w, int ss) {
    byte[] hdr = new byte[18];
    hdr[2] = 2;                                   // uncompressed true-colour
    hdr[12] = (byte)(w & 255); hdr[13] = (byte)(w >> 8);
    hdr[14] = (byte)(w & 255); hdr[15] = (byte)(w >> 8);
    hdr[16] = 32; hdr[17] = 8;                    // 32 bpp, 8 alpha bits, bottom-left origin
    using (var fs = new FileStream(path, FileMode.Create)) {
      fs.Write(hdr, 0, 18);
      for (int row = w - 1; row >= 0; row--) {    // y measured from the top; bottom row is written first
        for (int x = 0; x < w; x++) {
          double a = 0, al = 0;
          for (int sy = 0; sy < ss; sy++)
            for (int sx = 0; sx < ss; sx++) {
              double lum;
              double s = Shape(kind, x + (sx + 0.5) / ss, row + (sy + 0.5) / ss, w, out lum);
              a += s; al += s * lum;
            }
          double l = a > 0 ? al / a : 1;          // brightness of the covered part
          a /= ss * ss;
          int ai = (int)Math.Round(Math.Max(0, Math.Min(1, a)) * 255);
          byte li = (byte)Math.Round(Math.Max(0, Math.Min(1, l)) * 255);
          fs.WriteByte(li); fs.WriteByte(li); fs.WriteByte(li); fs.WriteByte((byte)ai);
        }
      }
    }
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
New-Item -ItemType Directory -Force $OutDir | Out-Null

[Tex]::Write("$OutDir\ring.tga",   "ring",   128, 4)   # HUD range ring
[Tex]::Write("$OutDir\disc.tga",   "disc",   32,  4)   # plain dot (enemy list line of sight)
[Tex]::Write("$OutDir\circle.tga", "circle", 32,  4)   # thin ring: target marker
[Tex]::Write("$OutDir\glow.tga",   "glow",   128, 2)   # soft HUD background
[Tex]::Write("$OutDir\arrow.tga",  "arrow",  64,  4)   # direction arrow, rotated in game
[Tex]::Write("$OutDir\player.tga", "arrow",  32,  4)   # player marker at the HUD centre
[Tex]::Write("$OutDir\pip.tga",    "pip",    32,  4)   # class-coloured dot with a black rim
[Tex]::Write("$OutDir\badge.tga",  "badge",  32,  4)   # stealth mark ring with black rims
[Tex]::Write("$OutDir\tri.tga",    "tri",    32,  4)   # enemy marker: class-coloured triangle, black rim

Get-ChildItem $OutDir | Select-Object Name, Length
