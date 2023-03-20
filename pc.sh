#! /bin/bash

# **********************************************************
# Copyright (c) 2020-2021 Xuhpclab. All rights reserved.
# Licensed under the MIT License.
# See LICENSE file for more information.
# **********************************************************

((num1=$1));echo $num1
((num2=$2));echo $num2
((num3=$3));echo $num3
((num4=$num1-$num2));echo $num4
((num5=$num3+$num4));echo $num5
#num4=$(([##16]num3));echo $num4
printf '%x\n' $num4
printf '%x\n' $num5
