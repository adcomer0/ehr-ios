#pragma once
#include <algorithm>
#include <cmath>

namespace ehr::keyboard {
struct Rect {double x,y,width,height;};
inline bool finite(Rect r){return std::isfinite(r.x)&&std::isfinite(r.y)&&std::isfinite(r.width)&&std::isfinite(r.height)&&r.width>=0&&r.height>=0;}
// Input/output are UIKit points in the host view's coordinate space. This is a
// bottom inset only: partial/floating occlusion is never expanded to full width.
inline double bottomInset(Rect bounds,Rect keyboard,double left,double right,double safeBottom){
    if(!finite(bounds)||bounds.width<=0||bounds.height<=0)return safeBottom;
    double original=std::isfinite(safeBottom)?std::clamp(safeBottom,0.0,bounds.height):0.0;
    if(!finite(keyboard)||keyboard.width<=0||keyboard.height<=0||!std::isfinite(left)||!std::isfinite(right)||left<0||right<0||left+right>=bounds.width)return original;
    double x=std::max(bounds.x,keyboard.x),y=std::max(bounds.y,keyboard.y);
    double maxX=std::min(bounds.x+bounds.width,keyboard.x+keyboard.width),maxY=std::min(bounds.y+bounds.height,keyboard.y+keyboard.height);
    if(maxX<=x||maxY<=y)return original;
    constexpr double tolerance=0.5;
    double safeLeft=bounds.x+left,safeRight=bounds.x+bounds.width-right,safeBottomEdge=bounds.y+bounds.height-original;
    if(x>safeLeft+tolerance||maxX<safeRight-tolerance||maxY<safeBottomEdge-tolerance)return original;
    return std::max(original,std::clamp(bounds.y+bounds.height-y,0.0,bounds.height));
}
}
