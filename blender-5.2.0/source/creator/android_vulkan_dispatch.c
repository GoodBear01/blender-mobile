/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** Android's libvulkan.so does not export VK_KHR_get_surface_capabilities2.
 * GHOST still references vkGetPhysicalDeviceSurfaceCapabilities2KHR, and
 * BIND_NOW then fails dlopen. Provide the symbol and fall back to 1.0 WSI. */

#include <string.h>
#include <vulkan/vulkan.h>

/* Device libvulkan.so (Pixel, Samsung, etc.) may omit KHR v2 WSI exports. */

VKAPI_ATTR VkResult VKAPI_CALL vkGetPhysicalDeviceSurfaceCapabilities2KHR(
    VkPhysicalDevice physicalDevice,
    const VkPhysicalDeviceSurfaceInfo2KHR *pSurfaceInfo,
    VkSurfaceCapabilities2KHR *pSurfaceCapabilities)
{
  if (pSurfaceInfo == NULL || pSurfaceCapabilities == NULL) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }
  /* Keep pNext intact; only fill the 1.0 capabilities block. */
  pSurfaceCapabilities->sType = VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_2_KHR;
  return vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
      physicalDevice, pSurfaceInfo->surface, &pSurfaceCapabilities->surfaceCapabilities);
}
