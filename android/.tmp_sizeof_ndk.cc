#include "RNA_types.hh"
template<int N> struct SizePrinter;
SizePrinter<sizeof(blender::PointerRNA)> x;
