/*=========================================================================

  Program:   Visualization Toolkit
  Module:    vtkSensorNode.cxx

  Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
  All rights reserved.
  See Copyright.txt or http://www.kitware.com/Copyright.htm for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.  See the above copyright notice for more information.

=========================================================================*/
#include "vtkSensorNode.h"

// --------------------------------------------------------------------includes

// -----------------------------------------------------------------------macro

// -----------------------------------------------------------------------cnstr
vtkSensorNode::vtkSensorNode()
{
  this->Enabled = false;
}

// -----------------------------------------------------------------------destr
vtkSensorNode::~vtkSensorNode()
{
}

bool vtkSensorNode::IsActive()
{
  return this->Enabled;
}


