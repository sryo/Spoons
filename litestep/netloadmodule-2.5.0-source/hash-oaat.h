#ifndef INC_ONE_AT_A_TIME_HASH_H
#define INC_ONE_AT_A_TIME_HASH_H

namespace hasher
{
/* One-at-a-time hash algorithm
 * http://burtleburtle.net/bob/hash/doobs.html
 * "This hash ... came from a set of requirements posed by Colin Plumb."
 *
 * full loop speed: 9n+9
 * inline speed:    5n+8
 * funnel-100:      none
 * collide-1000:   -0.09 
 *
 * C++ adaptation by RabidCow
 */
  class one_at_a_time
  {
  public:
    typedef unsigned hash_t;
    enum { chunk_len = 1 };

  protected:
    hash_t hash;

  public:
    one_at_a_time(void) : hash(0) { }

    inline void reset(void) { hash = 0; }
    inline void operator()(char key_i)
    {
      hash += key_i;
      hash += (hash << 10);
      hash ^= (hash >> 6);
    }
/*    inline void operator()(wchar_t key_i)
    {
      (*this)(static_cast<char>(key_i&0xff));
      (*this)(static_cast<char>(key_i>>8));
    }*/
    inline void finish(void)
    {
      hash += (hash << 3);
      hash ^= (hash >> 11);
      hash += (hash << 15);
    }

    inline operator hash_t(void) const { return hash; }
  };
}

#endif
