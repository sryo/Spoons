#ifndef RC_HASH_H_INCLUDED
#define RC_HASH_H_INCLUDED

#if defined (_MSC_VER) && (_MSC_VER >= 1020)
#pragma once
#endif

#include "hash-oaat.h"

namespace hash
{
  /* configuration */ 
  typedef char char_t;
  typedef const char_t * cstring_t;
  typedef char_t * string_t;
  typedef hasher::one_at_a_time hasher_t;
  typedef hasher_t::hash_t hash_t;
  inline bool str_eq(cstring_t a, cstring_t b)
  { return lstrcmp(a,b)==0; }

#ifndef RC_HASH_NO_EXCEPTIONS
  /* exception to throw, feel free to change type */ 
  extern cstring_t ENTRY_NOT_IN_TABLE;
  #ifdef RC_HASH_IMPL
  cstring_t ENTRY_NOT_IN_TABLE = "entry not in hash table";
  #endif
#endif

  template <typename char_t>
  inline hash_t str_hash(const char_t *src)
  {
    hasher_t hash;
    while (*src) hash(*src++);
    hash.finish();
    return hash;
  }

  struct hash_table_entry_t
  {
    union
    {
      int iNext;
      hash_table_entry_t *pNext;
    };
    hash_t hash;
    cstring_t key;
    LPARAM lData;
  };

  template <typename data_t>
  class HTE_access
  {
    hash_table_entry_t *pHTE;

  public:
    class HTE_data
    {
      data_t *pData;

    public:
      HTE_data(data_t &p) : pData(&p) { }
      HTE_data(data_t *&p) : pData(p)
      {
        if (!p)
          pData = p = new NLM_NOTHROW data_t;
      }
      operator data_t&() { return *pData; }
      data_t *addr(void) { return pData; }
      operator const data_t&() const { return *pData; }
      const data_t *addr(void) const { return pData; }
    };
    HTE_data data;

    HTE_access(hash_table_entry_t *p)
      : pHTE(p), data(reinterpret_cast<data_t*&>(p->lData))
    { }
  };

  /* optimization for <= 4 byte data types */ 
  HTE_access<int>::HTE_access(hash_table_entry_t *p) : pHTE(p), data(*(int*)&p->lData) { }
  HTE_access<char_t>::HTE_access(hash_table_entry_t *p) : pHTE(p), data(*(char_t*)&p->lData) { }
  HTE_access<cstring_t>::HTE_access(hash_table_entry_t *p) : pHTE(p), data(*(cstring_t*)&p->lData) { }

  template <typename data_t>
  class fixed_hash_table// : public hash_table_base<data_t>
  {
  protected:
    unsigned mask;
    hash_table_entry_t *pTable;

    hash_table_entry_t *raw_lookup(cstring_t key, hash_t hash)
    {
      hash_t i = hash&mask;
      /* direct lookup */ 
      hash_table_entry_t *p = &pTable[i];

      /* chained lookup */ 
      while (p)
      {
        if ((p->hash&mask) != i)
          return NULL;
        else if (p->hash==hash && str_eq(p->key,key))
          return p;
        else if (p->iNext == 0)
          return NULL;
        else
          p = &pTable[p->iNext-1];
      }

      return NULL;
    }

  public:
    /* l = size of table, must be a power of 2 */ 
    fixed_hash_table(unsigned l, hash_table_entry_t *p)
      : mask(l-1), pTable(p)
    { }

#ifndef RC_HASH_NO_EXCEPTIONS
    const data_t &operator[](cstring_t key)
    {
      const data_t *p;
      if (!lookup(p, key))
        throw ENTRY_NOT_IN_TABLE;
      return *p;
    }
#endif
    const data_t &operator()(cstring_t key, const data_t &def)
    {
      const data_t *p;
      if (!lookup(p, key))
        return def;
      return *p;
    }
    bool lookup(const data_t *&d, cstring_t key)
    { return lookup(d, key, str_hash(key)); }
    bool lookup(const data_t *&d, cstring_t key, hash_t hash)
    {
      hash_table_entry_t *pEntry = raw_lookup(key, hash);
      if (!pEntry) return false;
      HTE_access<data_t> p(pEntry);
      d = p.data.addr();
      return true;
    }
  };

} /* namespace hash */ 

#endif
