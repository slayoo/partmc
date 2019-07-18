/* Copyright (C) 2015-2018 Matthew Dawson
 * Licensed under the GNU General Public License version 2 or (at your
 * option) any later version. See the file COPYING for details.
 *
 * CMAQ_OH_HNO3 reaction solver functions
 *
*/
/** \file
 * \brief CMAQ_OH_HNO3 reaction solver functions
*/
extern "C"{
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "../rxns_gpu.h"

// TODO Lookup environmental indicies during initialization
#define TEMPERATURE_K_ env_data[0]
#define PRESSURE_PA_ env_data[1]

#define NUM_REACT_ int_data[0*n_rxn]
#define NUM_PROD_ int_data[1*n_rxn]
#define k0_A_ float_data[0*n_rxn]
#define k0_B_ float_data[1*n_rxn]
#define k0_C_ float_data[2*n_rxn]
#define k2_A_ float_data[3*n_rxn]
#define k2_B_ float_data[4*n_rxn]
#define k2_C_ float_data[5*n_rxn]
#define k3_A_ float_data[6*n_rxn]
#define k3_B_ float_data[7*n_rxn]
#define k3_C_ float_data[8*n_rxn]
#define SCALING_ float_data[9*n_rxn]
#define CONV_ float_data[10*n_rxn]
#define RATE_CONSTANT_ float_data[n_rxn*11]
#define NUM_INT_PROP_ 2
#define NUM_FLOAT_PROP_ 12
#define REACT_(x) (int_data[(NUM_INT_PROP_ + x)*n_rxn]-1)
#define PROD_(x) (int_data[(NUM_INT_PROP_ + NUM_REACT_ + x)*n_rxn]-1)
#define DERIV_ID_(x) int_data[(NUM_INT_PROP_ + NUM_REACT_ + NUM_PROD_ + x)*n_rxn]
#define JAC_ID_(x) int_data[(NUM_INT_PROP_ + 2*(NUM_REACT_+NUM_PROD_) + x)*n_rxn]
#define YIELD_(x) float_data[(NUM_FLOAT_PROP_ + x)*n_rxn]
#define INT_DATA_SIZE_ (NUM_INT_PROP_+(NUM_REACT_+2)*(NUM_REACT_+NUM_PROD_))
#define FLOAT_DATA_SIZE_ (NUM_FLOAT_PROP_+NUM_PROD_)

/** \brief Flag Jacobian elements used by this reaction
 *
 * \param rxn_data A pointer to the reaction data
 * \param jac_struct 2D array of flags indicating potentially non-zero
 *                   Jacobian elements
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
void * rxn_gpu_CMAQ_OH_HNO3_get_used_jac_elem(void *rxn_data, bool **jac_struct)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
  double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  for (int i_ind = 0; i_ind < NUM_REACT_; i_ind++) {
    for (int i_dep = 0; i_dep < NUM_REACT_; i_dep++) {
      jac_struct[REACT_(i_dep)][REACT_(i_ind)] = true;
    }
    for (int i_dep = 0; i_dep < NUM_PROD_; i_dep++) {
      jac_struct[PROD_(i_dep)][REACT_(i_ind)] = true;
    }
  }

  return (void*) &(float_data[FLOAT_DATA_SIZE_]);
}

/** \brief Update the time derivative and Jacbobian array indices
 *
 * \param model_data Pointer to the model data
 * \param deriv_ids Id of each state variable in the derivative array
 * \param jac_ids Id of each state variable combo in the Jacobian array
 * \param rxn_data Pointer to the reaction data
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
void * rxn_gpu_CMAQ_OH_HNO3_update_ids(ModelDatagpu *model_data, int *deriv_ids,
          int **jac_ids, void *rxn_data)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
  double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  // Update the time derivative ids
  for (int i=0; i < NUM_REACT_; i++)
	  DERIV_ID_(i) = deriv_ids[REACT_(i)];
  for (int i=0; i < NUM_PROD_; i++)
	  DERIV_ID_(i + NUM_REACT_) = deriv_ids[PROD_(i)];

  // Update the Jacobian ids
  int i_jac = 0;
  for (int i_ind = 0; i_ind < NUM_REACT_; i_ind++) {
    for (int i_dep = 0; i_dep < NUM_REACT_; i_dep++) {
      JAC_ID_(i_jac++) = jac_ids[REACT_(i_dep)][REACT_(i_ind)];
    }
    for (int i_dep = 0; i_dep < NUM_PROD_; i_dep++) {
      JAC_ID_(i_jac++) = jac_ids[PROD_(i_dep)][REACT_(i_ind)];
    }
  }
  return (void*) &(float_data[FLOAT_DATA_SIZE_]);
}

/** \brief Update reaction data for new environmental conditions
 *
 * For CMAQ_OH_HNO3 reaction this only involves recalculating the rate
 * constant.
 *
 * \param env_data Pointer to the environmental state array
 * \param rxn_data Pointer to the reaction data
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
__device__ void rxn_gpu_CMAQ_OH_HNO3_update_env_state(double *rate_constants,
   int n_rxn2,double *double_pointer_gpu, double *env_data, void *rxn_data)
{
  int n_rxn=n_rxn2;
  int *int_data = (int*) rxn_data;
  double *float_data = double_pointer_gpu;

  // Calculate the rate constant in (#/cc)
  double conv = CONV_ * PRESSURE_PA_ / TEMPERATURE_K_;
  double k2 = k2_A_
	  * (k2_C_==0.0 ? 1.0 : exp(k2_C_/TEMPERATURE_K_))
	  * (k2_B_==0.0 ? 1.0 :
                    pow(TEMPERATURE_K_/((double)300.0), k2_B_));
  double k3 = k3_A_ // [M] is included in k3_A_
	  * (k3_C_==0.0 ? 1.0 : exp(k3_C_/TEMPERATURE_K_))
	  * (k3_B_==0.0 ? 1.0 :
                    pow(TEMPERATURE_K_/((double)300.0), k3_B_))
	  * conv;
  RATE_CONSTANT_ = (k0_A_
	  * (k0_C_==0.0 ? 1.0 : exp(k0_C_/TEMPERATURE_K_))
	  * (k0_B_==0.0 ? 1.0 :
                  pow(TEMPERATURE_K_/((double)300.0), k0_B_))
	  + k3 / (((double)1.0) + k3 / k2)
	  ) * pow(conv, NUM_REACT_-1) * SCALING_;

  rate_constants[0] = RATE_CONSTANT_;

}

/** \brief Do pre-derivative calculations
 *
 * Nothing to do for CMAQ_OH_HNO3 reactions
 *
 * \param model_data Pointer to the model data, including the state array
 * \param rxn_data Pointer to the reaction data
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
void * rxn_gpu_CMAQ_OH_HNO3_pre_calc(ModelDatagpu *model_data, void *rxn_data)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
  double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  return (void*) &(float_data[FLOAT_DATA_SIZE_]);
}

/** \brief Calculate contributions to the time derivative \f$f(t,y)\f$ from
 * this reaction.
 *
 * \param model_data Pointer to the model data
 * \param deriv Pointer to the time derivative to add contributions to
 * \param rxn_data Pointer to the reaction data
 * \param time_step Current time step being computed (s)
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
#ifdef PMC_USE_SUNDIALS
__device__ void rxn_gpu_CMAQ_OH_HNO3_calc_deriv_contrib(double *rate_constants, double *state,
          double *deriv, void *rxn_data, double * double_pointer_gpu, double time_step, int deriv_length, int n_rxn2)
{
  int n_rxn=n_rxn2;
  int *int_data = (int*) rxn_data;
  double *float_data = double_pointer_gpu;

  // Calculate the reaction rate
  //double rate = RATE_CONSTANT_;
  double rate = rate_constants[0];
  for (int i_spec=0; i_spec<NUM_REACT_; i_spec++)
          rate *= state[REACT_(i_spec)];

  // Add contributions to the time derivative
  if (rate!=ZERO) {
    int i_dep_var = 0;
    for (int i_spec=0; i_spec<NUM_REACT_; i_spec++, i_dep_var++) {
      if (DERIV_ID_(i_dep_var) < 0) continue;
      //deriv[DERIV_ID_(i_dep_var)] -= rate;
      atomicAdd((double*)&(deriv[DERIV_ID_(i_dep_var)]),-rate);
    }
    for (int i_spec=0; i_spec<NUM_PROD_; i_spec++, i_dep_var++) {
      if (DERIV_ID_(i_dep_var) < 0) continue;
      // Negative yields are allowed, but prevented from causing negative
      // concentrations that lead to solver failures
      if (-rate*YIELD_(i_spec)*time_step <= state[PROD_(i_spec)]) {
        //deriv[DERIV_ID_(i_dep_var)] += rate*YIELD_(i_spec);
        atomicAdd((double*)&(deriv[DERIV_ID_(i_dep_var)]),rate*YIELD_(i_spec));
      }
    }
  }


}
#endif

/** \brief Calculate contributions to the time derivative \f$f(t,y)\f$ from
 * this reaction.
 *
 * \param model_data Pointer to the model data
 * \param deriv Pointer to the time derivative to add contributions to
 * \param rxn_data Pointer to the reaction data
 * \param time_step Current time step being computed (s)
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
#ifdef PMC_USE_SUNDIALS
void rxn_cpu_CMAQ_OH_HNO3_calc_deriv_contrib(double *rate_constants, double *state,
          double *deriv, void *rxn_data, double * double_pointer_gpu, double time_step, int deriv_length, int n_rxn2)
{
  int n_rxn=n_rxn2;
  int *int_data = (int*) rxn_data;
  double *float_data = double_pointer_gpu;

  // Calculate the reaction rate
  //double rate = RATE_CONSTANT_;
  double rate = rate_constants[0];
  for (int i_spec=0; i_spec<NUM_REACT_; i_spec++)
          rate *= state[REACT_(i_spec)];

  // Add contributions to the time derivative
  if (rate!=ZERO) {
    int i_dep_var = 0;
    for (int i_spec=0; i_spec<NUM_REACT_; i_spec++, i_dep_var++) {
      if (DERIV_ID_(i_dep_var) < 0) continue;
      deriv[DERIV_ID_(i_dep_var)] -= rate;
    }
    for (int i_spec=0; i_spec<NUM_PROD_; i_spec++, i_dep_var++) {
      if (DERIV_ID_(i_dep_var) < 0) continue;
      // Negative yields are allowed, but prevented from causing negative
      // concentrations that lead to solver failures
      if (-rate*YIELD_(i_spec)*time_step <= state[PROD_(i_spec)]) {
        deriv[DERIV_ID_(i_dep_var)] += rate*YIELD_(i_spec);
      }
    }
  }


}
#endif

/** \brief Calculate contributions to the Jacobian from this reaction
 *
 * \param model_data Pointer to the model data
 * \param J Pointer to the sparse Jacobian matrix to add contributions to
 * \param rxn_data Pointer to the reaction data
 * \param time_step Current time step being calculated (s)
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
#ifdef PMC_USE_SUNDIALS
__device__ void rxn_gpu_CMAQ_OH_HNO3_calc_jac_contrib(double *rate_constants, double *state, double *J,
          void *rxn_data, double * double_pointer_gpu, double time_step, int deriv_length, int n_rxn2)
{
  int n_rxn=n_rxn2;
  int *int_data = (int*) rxn_data;
  double *float_data = double_pointer_gpu;

  // Calculate the reaction rate
  //double rate = RATE_CONSTANT_;
  double rate = rate_constants[0];
  for (int i_spec=0; i_spec<NUM_REACT_; i_spec++)
          rate *= state[REACT_(i_spec)];

  // Add contributions to the Jacobian
  if (rate!=ZERO) {
    int i_elem = 0;
    for (int i_ind=0; i_ind<NUM_REACT_; i_ind++) {
      for (int i_dep=0; i_dep<NUM_REACT_; i_dep++, i_elem++) {
	if (JAC_ID_(i_elem) < 0) continue;
	J[JAC_ID_(i_elem)] -= rate / state[REACT_(i_ind)];
      }
      for (int i_dep=0; i_dep<NUM_PROD_; i_dep++, i_elem++) {
	if (JAC_ID_(i_elem) < 0) continue;
        // Negative yields are allowed, but prevented from causing negative
        // concentrations that lead to solver failures
        if (-rate*YIELD_(i_dep)*time_step <= state[PROD_(i_dep)]) {
	  J[JAC_ID_(i_elem)] += YIELD_(i_dep) * rate / state[REACT_(i_ind)];
        }
      }
    }
  }

  //return (void*) &(float_data[FLOAT_DATA_SIZE_]);

}
#endif

/** \brief Retrieve Int data size
 *
 * \param rxn_data Pointer to the reaction data
 * \return The data size of int array
 */
void * rxn_gpu_CMAQ_OH_HNO3_int_size(void *rxn_data)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
  double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  return (void*) float_data;
}

/** \brief Advance the reaction data pointer to the next reaction
 *
 * \param rxn_data Pointer to the reaction data
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
void * rxn_gpu_CMAQ_OH_HNO3_skip(void *rxn_data)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  return (void*) &(float_data[FLOAT_DATA_SIZE_]);
}

/** \brief Print the CMAQ_OH_HNO3 reaction parameters
 *
 * \param rxn_data Pointer to the reaction data
 * \return The rxn_data pointer advanced by the size of the reaction data
 */
void * rxn_gpu_CMAQ_OH_HNO3_print(void *rxn_data)
{
  int n_rxn=1;
  int *int_data = (int*) rxn_data;
  double *float_data = (double*) &(int_data[INT_DATA_SIZE_]);

  printf("\n\nCMAQ_OH_HNO3 reaction\n");
  for (int i=0; i<INT_DATA_SIZE_; i++)
    printf("  int param %d = %d\n", i, int_data[i]);
  for (int i=0; i<FLOAT_DATA_SIZE_; i++)
    printf("  float param %d = %le\n", i, float_data[i]);

  return (void*) &(float_data[FLOAT_DATA_SIZE_]);
}

#undef TEMPERATURE_K_
#undef PRESSURE_PA_

#undef NUM_REACT_
#undef NUM_PROD_
#undef k0_A_
#undef k0_B_
#undef k0_C_
#undef k2_A_
#undef k2_B_
#undef k2_C_
#undef k3_A_
#undef k3_B_
#undef k3_C_
#undef SCALING_
#undef CONV_
#undef RATE_CONSTANT_
#undef NUM_INT_PROP_
#undef NUM_FLOAT_PROP_
#undef REACT_
#undef PROD_
#undef DERIV_ID_
#undef JAC_ID_
#undef YIELD_
#undef INT_DATA_SIZE_
#undef FLOAT_DATA_SIZE_
}