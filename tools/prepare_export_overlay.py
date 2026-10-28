#!/usr/bin/env python3
"""Add a user-triggered allowlisted export picker to the current status panel."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path

def transform(data,expected):
    if hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Status overlay source hash mismatch')
    text=data.decode();replacements=[
        ('#import "EHRFullSourceRuntime.h"','#import "EHRFullSourceRuntime.h"\n#import "EHRExportSharing.h"'),
        ('@property(nonatomic,strong) UILabel *label;','@property(nonatomic,strong) UILabel *label;\n@property(nonatomic,strong) UIScrollView *statusScroll;\n@property(nonatomic,strong) UIButton *exportsButton;'),
        ('- (void)install {','- (void)shareExports {\n    if(self.window.rootViewController.presentedViewController)return;\n    [self.window.rootViewController presentViewController:EHRExportSharingController() animated:YES completion:nil];\n}\n- (void)install {'),
        ('    [self.panel addSubview:self.label];self.window.hidden=NO;[self refresh];','    self.statusScroll=[UIScrollView new];[self.panel addSubview:self.statusScroll];[self.statusScroll addSubview:self.label];\n    self.exportsButton=[UIButton buttonWithType:UIButtonTypeSystem];self.exportsButton.tintColor=UIColor.cyanColor;\n    [self.exportsButton setTitle:@"Share exports" forState:UIControlStateNormal];self.exportsButton.accessibilityLabel=@"Share EHR log and translation exports";\n    [self.exportsButton addTarget:self action:@selector(shareExports) forControlEvents:UIControlEventTouchUpInside];\n    [self.panel addSubview:self.exportsButton];self.window.hidden=NO;[self refresh];'),
        ('MIN(280,size.height-safe.top-safe.bottom-74)','MIN(360,size.height-safe.top-safe.bottom-74)'),
        ('    self.label.frame=CGRectInset(self.panel.bounds,14,12);','    self.statusScroll.frame=CGRectMake(14,12,MAX(0,self.panel.bounds.size.width-28),MAX(0,self.panel.bounds.size.height-80));\n    self.exportsButton.frame=CGRectMake(14,self.panel.bounds.size.height-56,self.panel.bounds.size.width-28,44);'),
        ('info[@"EHRReferenceGameVersion"]?:@"?",message];','info[@"EHRReferenceGameVersion"]?:@"?",message];\n    CGSize textSize=[self.label sizeThatFits:CGSizeMake(self.statusScroll.bounds.size.width,CGFLOAT_MAX)];\n    self.label.frame=CGRectMake(0,0,self.statusScroll.bounds.size.width,textSize.height);self.statusScroll.contentSize=self.label.bounds.size;')]
    for old,new in replacements:
        if text.count(old)!=1:raise ValueError('Exact current status overlay anchor required: '+old[:60])
        text=text.replace(old,new,1)
    if 'self.button.frame=CGRectMake(right-132,safe.top+10,132,44);' not in text:raise ValueError('Existing44pt status button must be preserved')
    return text.encode()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--input-sha256',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    try:
        if a.output.exists():raise ValueError('Fresh output directory required')
        before=a.input.read_bytes();after=transform(before,a.input_sha256);a.output.mkdir(parents=True);(a.output/'EHRFullSourceOverlay.mm').write_bytes(after)
        (a.output/'export-overlay.json').write_text(json.dumps({'schema':1,'input':str(a.input.resolve()),'inputSha256':a.input_sha256,'outputSha256':hashlib.sha256(after).hexdigest(),'statusButton44Preserved':True,'presentationOnlyAfterUserTap':True,'managedAbiChanged':False},indent=2)+'\n')
    except (OSError,ValueError) as error:p.exit(2,str(error)+'\n')
if __name__=='__main__':main()
