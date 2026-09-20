#include "RNA_types.hh"
#include <cstdio>
int main() {
  printf("PointerRNA %zu\n", sizeof(blender::PointerRNA));
  printf("AncestorPointerRNA %zu\n", sizeof(blender::AncestorPointerRNA));
  printf("Vector %zu\n", sizeof(blender::Vector<blender::AncestorPointerRNA, 2>));
  return 0;
}
