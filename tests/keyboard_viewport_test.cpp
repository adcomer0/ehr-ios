#include "../native/EHRKeyboardViewport.hpp"
#include <iostream>
#include <limits>
#include <stdexcept>
static size_t checks=0;
static void check(bool value,const char*label){checks++;if(!value)throw std::runtime_error(label);}
int main(){
    try{
        using namespace ehr::keyboard;
        for(double width:{320.,375.,390.,430.,667.,852.,956.,1024.,1366.})
        for(double height:{320.,375.,440.,667.,844.,956.,1024.})
        for(double safe:{0.,21.,34.})
        for(double origin:{0.,17.}){
            Rect bounds{origin,origin,width,height};
            check(bottomInset(bounds,{origin,origin+height-safe,width,safe},0,0,safe)==safe,"hidden guide preserves safe area");
            check(bottomInset(bounds,{0,0,0,0},0,0,safe)==safe,"empty guide preserves safe area");
            double keyHeight=std::min(216.,height-60),top=origin+height-keyHeight;
            Rect docked{origin,top,width,keyHeight};
            check(bottomInset(bounds,docked,0,0,safe)==keyHeight,"docked full-width height");
            check(bottomInset(bounds,{origin-20,top,width+40,keyHeight+50},0,0,safe)==keyHeight,"clipped offscreen keyboard");
            check(bottomInset(bounds,{origin+width*.1,top,width*.8,keyHeight},0,0,safe)==safe,"floating partial width unchanged");
            check(bottomInset(bounds,{origin,top-70,width,30},0,0,safe)==safe,"undocked full-width gap unchanged");
            check(bottomInset(bounds,{origin+width+10,top,width,keyHeight},0,0,safe)==safe,"other-window outside frame ignored");
            check(bottomInset(bounds,{origin,origin+height+20,width,keyHeight},0,0,safe)==safe,"hidden offscreen keyboard");
            check(bottomInset(bounds,{origin+10,top,width-20,keyHeight},10,10,safe)==keyHeight,"safe width obstruction excludes side areas");
            check(bottomInset(bounds,{origin+11,top,width-21,keyHeight},10,10,safe)==safe,"one-point content gap not full-width");
            for(double pixels:{1.,2.,3.})check(bottomInset(bounds,docked,0,0,safe)*pixels==keyHeight*pixels,"inset converts to logical pixels once");
        }
        double nan=std::numeric_limits<double>::quiet_NaN(),inf=std::numeric_limits<double>::infinity();
        for(Rect invalid: {Rect{0,0,nan,200},Rect{0,0,inf,200},Rect{0,0,-1,200},Rect{0,0,300,-1},Rect{nan,0,300,200}})check(bottomInset({0,0,390,844},invalid,0,0,34)==34,"invalid keyboard ignored");
        check(bottomInset({0,0,390,844},{0,600,390,244},0,0,nan)==244,"invalid safe inset sanitized");
        check(bottomInset({0,0,390,844},{0,600,390,244},200,200,34)==34,"invalid content width rejected");
        std::cout<<"PASS "<<checks<<" numeric keyboard viewport checks; no keyboard presentation, UIKit/game/account/network actions\n";return 0;
    }catch(const std::exception&error){std::cerr<<error.what()<<"\n";return 1;}
}
