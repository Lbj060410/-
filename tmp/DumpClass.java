import java.io.*;
import java.nio.file.*;

public class DumpClass {
  static class CPEntry { int tag; Object value; }
  static DataInputStream in;
  static CPEntry[] cp;

  static String utf(int idx) {
    if (idx <= 0 || idx >= cp.length || cp[idx] == null) return "#" + idx;
    if (cp[idx].tag == 1) return (String) cp[idx].value;
    return String.valueOf(cp[idx].value);
  }

  static String className(int idx) {
    if (idx <= 0 || idx >= cp.length || cp[idx] == null) return "#" + idx;
    if (cp[idx].tag == 7) return utf((Integer) cp[idx].value);
    return String.valueOf(cp[idx].value);
  }

  static void skipMember() throws Exception {
    in.readUnsignedShort();
    in.readUnsignedShort();
    in.readUnsignedShort();
    int ac = in.readUnsignedShort();
    for (int j = 0; j < ac; j++) {
      in.readUnsignedShort();
      int len = in.readInt();
      in.skipBytes(len);
    }
  }

  public static void main(String[] args) throws Exception {
    Path path = Paths.get(args[0]);
    in = new DataInputStream(new ByteArrayInputStream(Files.readAllBytes(path)));
    if (in.readInt() != 0xCAFEBABE) throw new RuntimeException("bad class");
    in.readUnsignedShort();
    in.readUnsignedShort();
    int cpCount = in.readUnsignedShort();
    cp = new CPEntry[cpCount];
    for (int i = 1; i < cpCount; i++) {
      int tag = in.readUnsignedByte();
      CPEntry e = new CPEntry(); e.tag = tag;
      switch(tag) {
        case 1: e.value = in.readUTF(); break;
        case 3: e.value = in.readInt(); break;
        case 4: e.value = in.readFloat(); break;
        case 5: e.value = in.readLong(); cp[i] = e; i++; continue;
        case 6: e.value = in.readDouble(); cp[i] = e; i++; continue;
        case 7: case 8: case 16: e.value = in.readUnsignedShort(); break;
        case 9: case 10: case 11: case 12: case 18:
          e.value = new int[]{in.readUnsignedShort(), in.readUnsignedShort()}; break;
        case 15:
          e.value = new int[]{in.readUnsignedByte(), in.readUnsignedShort()}; break;
        default: throw new RuntimeException("tag=" + tag);
      }
      cp[i] = e;
    }
    in.readUnsignedShort();
    int thisCls = in.readUnsignedShort();
    int superCls = in.readUnsignedShort();
    System.out.println("CLASS " + className(thisCls) + " extends " + className(superCls));
    System.out.println("-- CONSTANTS --");
    for (int i = 1; i < cp.length; i++) {
      CPEntry e = cp[i];
      if (e == null) continue;
      if (e.tag == 1) {
        String s = (String)e.value;
        if (s.matches(".*(255\\.255|snapshot|decoder|camera|search|http|login|pass|IP|socket).*")) {
          System.out.println(i + " UTF8 " + s);
        }
      } else if (e.tag == 3) {
        int v = (Integer)e.value;
        if (v < 100000) {
          System.out.println(i + " INT " + v);
        }
      }
    }
    int ifaces = in.readUnsignedShort();
    for (int i = 0; i < ifaces; i++) in.readUnsignedShort();
    int fields = in.readUnsignedShort();
    for (int i = 0; i < fields; i++) skipMember();
    int methods = in.readUnsignedShort();
    System.out.println("-- METHODS --");
    for (int i = 0; i < methods; i++) {
      in.readUnsignedShort();
      String name = utf(in.readUnsignedShort());
      String desc = utf(in.readUnsignedShort());
      System.out.println(name + " " + desc);
      int ac = in.readUnsignedShort();
      for (int j = 0; j < ac; j++) {
        String attr = utf(in.readUnsignedShort());
        int len = in.readInt();
        if ("Code".equals(attr)) {
          in.readUnsignedShort();
          in.readUnsignedShort();
          int codeLen = in.readInt();
          byte[] code = new byte[codeLen];
          in.readFully(code);
          System.out.print("  code:");
          for (byte b : code) System.out.printf(" %02X", b & 0xFF);
          System.out.println();
          int exCount = in.readUnsignedShort();
          in.skipBytes(exCount * 8);
          int subAttr = in.readUnsignedShort();
          for (int k = 0; k < subAttr; k++) {
            in.readUnsignedShort();
            int sl = in.readInt();
            in.skipBytes(sl);
          }
        } else {
          in.skipBytes(len);
        }
      }
    }
  }
}
