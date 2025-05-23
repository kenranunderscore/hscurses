-- Copyright (c) 2002-2004 John Meacham (john at repetae dot net)
-- Copyright (c) 2004      Don Stewart - http://www.cse.unsw.edu.au/~dons
--
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 2.1 of the License, or (at your option) any later version.
--
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public
-- License along with this library; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA


module UI.HSCurses.CWString (
    -- utf8 versions
    withUTF8String,
    withUTF8StringLen,
    newUTF8String,
    newUTF8StringLen,
    peekUTF8String,
    peekUTF8StringLen,

        -- WChar stuff
#ifdef HAVE_WCHAR_H
    withCWString,
    withCWStringLen,
    newCWString,
    newCWStringLen,
    peekCWString,
    peekCWStringLen,
    wcharIsUnicode,
    CWChar,
    CWString,
    CWStringLen,
#endif

    -- Locale versions
    withLCString,
    withLCStringLen,
    newLCString,
    newLCStringLen,
    peekLCStringLen,
    peekLCString,
) where

import Data.Bits (Bits (shift, (.&.), (.|.)))
import Data.Char (chr, ord)
import Foreign.C.String

#if __GLASGOW_HASKELL__ < 603
import GHC.Exts
#endif

#ifdef HAVE_WCHAR_H

import Foreign.C.Types

#include <wchar.h>
#include <limits.h>
#include <stdlib.h>

type CWChar = (#type wchar_t)
type CWString = Ptr CWChar
type CWStringLen = (CWString, Int)

fi :: (Integral a, Num b) => a -> b
fi x = fromIntegral x

-------------------
-- CWChar functions
-------------------

{-# INLINE wcharIsUnicode #-}
wcharIsUnicode :: Bool

#if defined(__STDC_ISO_10646__)

wcharIsUnicode = True

-- support functions
wNUL :: CWChar
wNUL = 0

#ifndef __GLASGOW_HASKELL__

pairLength :: String -> CString -> CStringLen
pairLength = flip (,) . length

cwCharsToChars :: [CWChar] -> [Char]
cwCharsToChars xs = map castCWCharToChar xs
charsToCWChars :: [Char] -> [CWChar]
charsToCWChars xs = map castCharToCWChar xs

#endif

-- __STDC_ISO_10646__

castCWCharToChar :: CWChar -> Char
castCWCharToChar ch = chr (fromIntegral ch)

castCharToCWChar :: Char -> CWChar
castCharToCWChar ch = fromIntegral (ord ch)

peekCWString :: CWString -> IO String
#ifndef __GLASGOW_HASKELL__
peekCString cp = do cs <- peekArray0 wNUL cp; return (cwCharsToChars cs)
#else
peekCWString cp = loop 0
  where
    loop i = do
        val <- peekElemOff cp i
        if val == wNUL
            then return []
            else do
                rest <- loop (i + 1)
                return (castCWCharToChar val : rest)
#endif

peekCWStringLen :: CWStringLen -> IO String
#ifndef __GLASGOW_HASKELL__
peekCWStringLen (cp, len) = do cs <- peekArray len cp; return (cwCharsToChars cs)
#else
peekCWStringLen (cp, len) = loop 0
  where
    loop i
        | i == len = return []
        | otherwise = do
            val <- peekElemOff cp i
            rest <- loop (i + 1)
            return (castCWCharToChar val : rest)
#endif

newCWString :: String -> IO CWString
#ifndef __GLASGOW_HASKELL__
newCWString = newArray0 wNUL . charsToCWChars
#else
newCWString str = do
  ptr <- mallocArray0 (length str)
  let
        go [] n##   = pokeElemOff ptr (I## n##) wNUL
        go (c:cs) n## = do pokeElemOff ptr (I## n##) (castCharToCWChar c); go cs (n## +## 1##)
  go str 0##
  return ptr
#endif

newCWStringLen :: String -> IO CWStringLen
#ifndef __GLASGOW_HASKELL__
newCWStringLen str = do
    a <- newArray (charsToCWChars str)
    return
    (pairLength str a)
#else
newCWStringLen str = do
  ptr <- mallocArray0 len
  let
        go [] _       = return ()
        go (c:cs) n## = do pokeElemOff ptr (I## n##) (castCharToCWChar c); go cs (n## +## 1##)
  go str 0##
  return (ptr, len)
  where
    len = length str
#endif

withCWString :: String -> (CWString -> IO a) -> IO a
#ifndef __GLASGOW_HASKELL__
withCWString = withArray0 wNUL . charsToCWChars
#else
withCWString str f =
  allocaArray0 (length str) $ \ptr ->
      let
        go [] n##     = pokeElemOff ptr (I## n##) wNUL
        go (c:cs) n## = do pokeElemOff ptr (I## n##) (castCharToCWChar c); go cs (n## +## 1##)
      in do
      go str 0##
      f ptr
#endif

withCWStringLen :: String -> (CWStringLen -> IO a) -> IO a
#ifndef __GLASGOW_HASKELL__
withCWStringLen str act = withArray (charsToCWChars str) $ act . pairLength str
#else
withCWStringLen str f =
  allocaArray len $ \ptr ->
      let
        go [] _       = return ()
        go (c:cs) n## = do pokeElemOff ptr (I## n##) (castCharToCWChar c); go cs (n## +## 1##)
      in do
      go str 0##
      f (ptr,len)
  where
    len = length str
#endif


#else
-- no __STDC_ISO_10646__
wcharIsUnicode = False
#endif

newtype MBState = MBState {_mbstate :: (Ptr MBState)}

withMBState :: (MBState -> IO a) -> IO a
withMBState act = allocaBytes (# const sizeof (mbstate_t)) (\mb -> c_memset mb 0 (# const sizeof (mbstate_t)) >> act (MBState mb))

clearMBState :: MBState -> IO ()
clearMBState (MBState mb) = c_memset mb 0 (# const sizeof (mbstate_t)) >> return ()

wcsrtombs :: CWString -> (CString, CSize) -> IO CSize
wcsrtombs wcs (cs, len) =
    alloca
        ( \p ->
            poke p wcs
                >> withMBState
                    ( \mb ->
                        wcsrtombs' p cs len mb
                    )
        )
  where
    wcsrtombs' p cs' len' mb = do
        x <- c_wcsrtombs cs p len' mb
        case x of
            -1 -> do
                sp <- peek p
                poke sp ((fi (ord '?')) :: CWChar)
                poke p wcs
                clearMBState mb
                wcsrtombs' p cs' len' mb
            e | e >= 0 && e <= len' -> do
                let ep = advancePtr cs' (fi e)
                poke ep (fi (0 :: Int))
                return x
            e -> error $ "HSCurses.CWString.wcsrtombs: impossible case: " ++ show e

foreign import ccall unsafe hs_get_mb_cur_max :: IO Int

mb_cur_max :: Int
mb_cur_max = unsafePerformIO hs_get_mb_cur_max

foreign import ccall unsafe "stdlib.h wcsrtombs"
    c_wcsrtombs :: CString -> (Ptr (Ptr CWChar)) -> CSize -> MBState -> IO CSize

foreign import ccall unsafe "string.h memset"
    c_memset :: Ptr a -> CInt -> CSize -> IO (Ptr a)

foreign import ccall unsafe "stdlib.h mbstowcs"
    c_mbstowcs :: CWString -> CString -> CSize -> IO CSize

mbstowcs ::
    CWString ->
    Foreign.C.String.CString ->
    Foreign.C.Types.CSize ->
    IO Foreign.C.Types.CSize
mbstowcs a b s = throwIf (== -1) (const "mbstowcs") $ c_mbstowcs a b s

peekLCString :: CString -> IO String
peekLCString cp = do
    sz <- mbstowcs nullPtr cp 0
    allocaArray (fi $ sz + 1) (\wcp -> mbstowcs wcp cp (sz + 1) >> peekCWString wcp)

-- TODO fix for embeded NULs
peekLCStringLen :: CStringLen -> IO String
peekLCStringLen (cp, len) = allocaBytes (len + 1) $ \ncp -> do
    copyBytes ncp cp len
    pokeElemOff ncp len 0
    peekLCString ncp

newLCString :: String -> IO CString
newLCString s =
    withCWString s $ \wcs -> do
        cs <- mallocArray0 alen
        wcsrtombs wcs (cs, fi alen)
        return cs
  where
    alen = mb_cur_max * length s

newLCStringLen :: String -> IO CStringLen
newLCStringLen str = newLCString str >>= \cs -> return (pairLength1 str cs)

withLCString :: String -> (CString -> IO a) -> IO a
withLCString s a =
    withCWString s $ \wcs ->
        allocaArray0 alen $ \cs ->
            wcsrtombs wcs (cs, fi alen) >> a cs
  where
    alen = mb_cur_max * length s

withLCStringLen :: String -> (CStringLen -> IO a) -> IO a
withLCStringLen s a =
    withCWString s $ \wcs ->
        allocaArray0 alen $ \cs -> do
            sz <- wcsrtombs wcs (cs, fi alen)
            a (cs, fi sz)
  where
    alen = mb_cur_max * length s

pairLength1 :: String -> CString -> CStringLen
pairLength1 = flip (,) . length

#else
-- -----------------------------------------------------------
-- no CF_WCHAR_SUPPORT (OpenBSD)

withLCString :: String -> (Foreign.C.String.CString -> IO a) -> IO a
withLCString = withCString

withLCStringLen :: String -> (Foreign.C.String.CStringLen -> IO a) -> IO a
withLCStringLen = withCStringLen

newLCString :: String -> IO Foreign.C.String.CString
newLCString = newCString

newLCStringLen :: String -> IO Foreign.C.String.CStringLen
newLCStringLen = newCStringLen

peekLCString :: Foreign.C.String.CString -> IO String
peekLCString = peekCString

peekLCStringLen :: Foreign.C.String.CStringLen -> IO String
peekLCStringLen = peekCStringLen

#endif
-- no CF_WCHAR_SUPPORT

-----------------
-- UTF8 versions
-----------------

withUTF8String :: String -> (CString -> IO a) -> IO a
withUTF8String hsStr = withCString (toUTF hsStr)

withUTF8StringLen :: String -> (CStringLen -> IO a) -> IO a
withUTF8StringLen hsStr = withCStringLen (toUTF hsStr)

newUTF8String :: String -> IO CString
newUTF8String = newCString . toUTF

newUTF8StringLen :: String -> IO CStringLen
newUTF8StringLen = newCStringLen . toUTF

peekUTF8String :: CString -> IO String
peekUTF8String strPtr = fmap fromUTF $ peekCString strPtr

peekUTF8StringLen :: CStringLen -> IO String
peekUTF8StringLen strPtr = fmap fromUTF $ peekCStringLen strPtr

-- these should read and write directly from/to memory.
-- A first pass will be needed to determine the size of the allocated region

toUTF :: String -> String
toUTF [] = []
toUTF (x : xs)
    | ord x <= 0x007F = x : toUTF xs
    | ord x <= 0x07FF =
        chr (0xC0 .|. ((ord x `shift` (-6)) .&. 0x1F))
            : chr (0x80 .|. (ord x .&. 0x3F))
            : toUTF xs
    | otherwise =
        chr (0xE0 .|. ((ord x `shift` (-12)) .&. 0x0F))
            : chr (0x80 .|. ((ord x `shift` (-6)) .&. 0x3F))
            : chr (0x80 .|. (ord x .&. 0x3F))
            : toUTF xs

fromUTF :: String -> String
fromUTF [] = []
fromUTF (al@(x : xs))
    | ord x <= 0x7F = x : fromUTF xs
    | ord x <= 0xBF = err
    | ord x <= 0xDF = twoBytes al
    | ord x <= 0xEF = threeBytes al
    | otherwise = err
  where
    twoBytes (x1 : x2 : xs') =
        chr
            ( ((ord x1 .&. 0x1F) `shift` 6)
                .|. (ord x2 .&. 0x3F)
            )
            : fromUTF xs'
    twoBytes _ = error "fromUTF: illegal two byte sequence"

    threeBytes (x1 : x2 : x3 : xs') =
        chr
            ( ((ord x1 .&. 0x0F) `shift` 12)
                .|. ((ord x2 .&. 0x3F) `shift` 6)
                .|. (ord x3 .&. 0x3F)
            )
            : fromUTF xs'
    threeBytes _ = error "fromUTF: illegal three byte sequence"

    err = error "fromUTF: illegal UTF-8 character"
